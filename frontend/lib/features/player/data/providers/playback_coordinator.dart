import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/datasources/audio_player_datasource.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_coordinator.freezed.dart';

@freezed
sealed class PlaybackState with _$PlaybackState {
  const factory initial() = PlaybackInitial;
  const factory playing({
    required Media media,
    required MediaType type,
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
    @Default(1.0) double speed,
    Duration? savedPosition,
  }) = PlaybackPlaying;
  const factory completed() = PlaybackCompleted;
  const factory loading() = PlaybackLoading;
  const factory error({required String message}) = PlaybackError;
}

/// Manages unified playback across audio and video.
/// Handles mutual exclusion: starting video stops audio and vice versa.
///
/// Аудио-очередь живёт в mpv (`Player.open(Playlist(...))`), поэтому
/// переход между треками — одна mpv-команда, а не переоткрытие URL.
/// Все подписки на потоки плеера — постоянные (создаются один раз):
/// раньше они пересоздавались на каждый переход, и событие «трек
/// доиграл», пришедшее в это окно, терялось безвозвратно.
class PlaybackCoordinator extends Notifier<PlaybackState>
    implements PlaybackController {
  late final AudioPlaybackSource _audioPlayer;
  late final String _baseUrl;

  @override
  PlaybackState build() {
    _audioPlayer = ref.watch(audioPlayerDatasourceProvider);
    _baseUrl = ref.watch(baseUrlProvider);
    _subscribeAudioStreams();
    // Токен протухает на час, а mpv берёт Authorization из плейлиста в
    // момент загрузки каждого файла. Без перезагрузки плейлиста длинная
    // фоновая очередь умирала бы на 401 молча.
    ref.listen<String?>(settingsProvider.select((s) => s.settings.authToken), (
      previous,
      next,
    ) {
      if (previous == null || next == null) return;
      _onTokenChanged();
    });
    // В Notifier (Riverpod 2.x) нет переопределяемого dispose() —
    // cleanup при утилизации провайдера делаем через onDispose.
    ref.onDispose(() {
      _disposed = true;
      _cancelSubscriptions();
      _cancelProgressTimer();
      unawaited(_playlistIndexCtl.close());
    });
    return const PlaybackState.initial();
  }

  /// Порог для resume-оверлея: позиции не больше этого значения
  /// применяются сразу (видео продолжается без диалога).
  static const _resumeThreshold = Duration(seconds: 5);

  /// Интервал автосохранения прогресса во время воспроизведения.
  static const _progressSaveInterval = Duration(seconds: 10);

  /// Потолок на открытие/запуск медиа. Без него зависший player.open()
  /// навсегда блокирует [_playChain]: ни один следующий play() не дойдёт
  /// до конца, и плеер «замирает» без единой ошибки в UI.
  static const _loadTimeout = Duration(seconds: 20);

  /// Последний начатый тип медиа. Нужен в stop(): при loading/completed
  /// состояние не хранит тип, а остановить физический плеер всё равно
  /// необходимо (например, закрытие экрана во время загрузки видео).
  MediaType? _lastType;

  /// Поколение play-операций: инкрементируется при каждой загрузке
  /// очереди/трека и при stop(). Проверяется после каждого await — если
  /// stop() или новая операция прервала текущую, она не должна
  /// перезапускать воспроизведение и переписывать состояние.
  int _playGeneration = 0;

  /// Используется для ленивого чтения токена (чтобы его обновление не
  /// сбрасывало состояние воспроизведения) и координации с видеоплеером.
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;

  final StreamController<int> _playlistIndexCtl =
      StreamController<int>.broadcast();

  bool _audioSubscribed = false;
  bool _videoSubscribed = false;
  bool _disposed = false;

  /// Идёт загрузка очереди: события индекса mpv в этот момент игнорируются,
  /// состояние выставит [_startQueue].
  bool _loadingQueue = false;

  /// mpv играет по плейлисту (а не по одиночному Media). Разные очереди
  /// (видео, смешанные) остаются на поштучном открытии.
  bool _audioPlaylistActive = false;

  /// Последний токен, под которым загружен плейлист.
  String? _playlistToken;

  /// Идёт ли сейчас mpv-команда плейлиста. Повторный вход изнутри неё
  /// — признак рекурсии маршрутизации (см. [_playlistCommand]).
  bool _inPlaylistCommand = false;

  /// Последнее значение playing-сигнала плеера, независимо от состояния UI.
  /// Нужно [_onMpvPlaylistIndex]: mpv при смене элемента не всегда снимает
  /// паузу (удаление играющего последнего трека шлёт `playing: false` перед
  /// новым индексом), а дефолт `isPaused: false` в новом состоянии показал
  /// бы UI «играет» при стоящем плеере. Источник тот же, что у
  /// `engine.isPlaying`, поэтому сверка с движком не нужна.
  bool _lastPlayingSignal = false;

  /// Lazily reads the video player datasource. Using ref.read instead of
  /// ref.watch prevents this long-lived provider from keeping the
  /// autoDispose videoPlayerDatasourceProvider alive.
  VideoPlaybackSource get _videoPlayer =>
      ref.read(videoPlayerDatasourceProvider);

  /// Сериализует сохранения прогресса: параллельные вызовы (completed
  /// при завершении трека, save таймера, сохранения предыдущего трека
  /// при переключении) выполняются строго по очереди, чтобы более
  /// позднее сохранение не перезаписало более раннее (гонка
  /// completed:true vs completed:false).
  Future<void> _saveChain = Future.value();

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    _audioSubscribed = false;
    _videoSubscribed = false;
  }

  void _cancelProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// Serializes concurrent play() calls through a Future chain: each call
  /// waits for the previous one to finish, ensuring only the latest media
  /// actually starts playing. Errors are swallowed in the chain itself
  /// (otherwise one failed play would block all subsequent calls), while
  /// each caller still receives its own result.
  Future<void> _playChain = Future.value();

  Future<void> _serialize(Future<void> Function() action) {
    final result = _playChain.then((_) => action());
    _playChain = result.catchError((_) {});
    return result;
  }

  void _subscribe<T>(Stream<T> stream, void Function(T) onNext) {
    if (_disposed) return;
    final sub = stream.listen(onNext);
    _subscriptions.add(sub);
  }

  /// Подписки аудиоплеера живут всё время жизни координатора: потоки
  /// media_kit привязаны к player, а не к отдельному треку.
  void _subscribeAudioStreams() {
    if (_audioSubscribed) return;
    _audioSubscribed = true;
    _subscribe(_audioPlayer.positionStream, (pos) {
      if (state is PlaybackPlaying && _lastType == MediaType.audio) {
        state = (state as PlaybackPlaying).copyWith(position: pos);
      }
    });
    _subscribe(_audioPlayer.durationStream, (dur) {
      if (state is PlaybackPlaying && _lastType == MediaType.audio) {
        state = (state as PlaybackPlaying).copyWith(duration: dur);
      }
    });
    _subscribe(_audioPlayer.playingStream, (playing) {
      _lastPlayingSignal = playing;
      if (state is PlaybackPlaying && _lastType == MediaType.audio) {
        state = (state as PlaybackPlaying).copyWith(isPaused: !playing);
      }
    });
    _subscribe(
      _audioPlayer.completedStream,
      (completed) => unawaited(_onCompleted(completed)),
    );
    _subscribe(_audioPlayer.errorStream, _onPlayerError);
    _subscribe(_audioPlayer.bufferingStream, _onBuffering);
    _subscribe(_audioPlayer.playlistIndexStream, _onMpvPlaylistIndex);
  }

  void _subscribeVideoStreams() {
    if (_videoSubscribed) return;
    _videoSubscribed = true;
    _subscribe(_videoPlayer.positionStream, (pos) {
      if (state is PlaybackPlaying && _lastType == MediaType.video) {
        state = (state as PlaybackPlaying).copyWith(position: pos);
      }
    });
    _subscribe(_videoPlayer.durationStream, (dur) {
      if (state is PlaybackPlaying && _lastType == MediaType.video) {
        state = (state as PlaybackPlaying).copyWith(duration: dur);
      }
    });
    _subscribe(_videoPlayer.playingStream, (playing) {
      if (state is PlaybackPlaying && _lastType == MediaType.video) {
        state = (state as PlaybackPlaying).copyWith(isPaused: !playing);
      }
    });
    _subscribe(
      _videoPlayer.completedStream,
      (completed) => unawaited(_onCompleted(completed)),
    );
    _subscribe(_videoPlayer.errorStream, _onPlayerError);
    _subscribe(_videoPlayer.bufferingStream, _onBuffering);
  }

  @override
  Stream<int> get playlistIndexStream => _playlistIndexCtl.stream;

  // --------------------------------------------------------------------------
  // Загрузка очереди / отдельного трека
  // --------------------------------------------------------------------------

  @override
  Future<void> startQueue({required int startIndex}) async {
    final queue = ref.read(playQueueProvider);
    if (queue.items.isEmpty) return;
    final index = startIndex.clamp(0, queue.items.length - 1);
    await _guardedStart(index);
  }

  /// Загрузка очереди/трека с единой обработкой ошибок: результат виден в
  /// UI как PlaybackState.error и попадает в лог. Раньше исключение просто
  /// глоталось, и плеер выглядел «замершим».
  Future<void> _guardedStart(int index) async {
    try {
      await _serialize(() => _startQueue(index));
    } catch (e, s) {
      AppLogger.error('Playback start failed at index $index', e, s);
      _audioPlaylistActive = false;
      if (!_disposed) state = PlaybackState.error(message: e.toString());
      rethrow;
    }
  }

  @override
  Future<void> enqueue(List<Media> items) async {
    if (items.isEmpty || !_audioPlaylistActive) return;
    final entries = await _buildEntries(items);
    await _serialize(() async {
      await _audioPlayer.appendToPlaylist(entries);
    });
  }

  Future<void> _startQueue(int startIndex, {Duration? resumeAt}) async {
    final queue = ref.read(playQueueProvider);
    if (queue.items.isEmpty) return;
    final index = startIndex.clamp(0, queue.items.length - 1);
    final allAudio = queue.items.every((m) => m.type == MediaType.audio);

    final generation = ++_playGeneration;
    _cancelProgressTimer();
    // Тип известен до загрузки: stop() должен остановить нужный плеер,
    // даже если вызов придёт посередине открытия.
    _lastType = queue.items[index].type;
    _audioPlaylistActive = allAudio;
    _loadingQueue = allAudio;

    // Сохраняем позицию текущего видео до переключения: 10-секундный
    // таймер мог не успеть, и прогресс терялся бы при уходе на другой
    // трек. При автопродвижении безопасно — там уже PlaybackLoading.
    // Состояние запоминаем ДО перевода в loading: после loading
    // проверка `state is PlaybackPlaying` уже не сработает.
    final previous = state;
    if (previous is PlaybackPlaying && previous.media.type == MediaType.video) {
      await _saveProgress(
        previous.media.id,
        previous.position,
        previous.duration ?? Duration.zero,
      );
    }
    // _saveProgress ходит в сеть — за это окно мог прийти stop().
    // Без проверки generation следующая строка затерела бы
    // PlaybackInitial на loading, и состояние залипло бы навсегда.
    if (generation != _playGeneration) return;

    state = const PlaybackState.loading();

    try {
      if (allAudio) {
        final entries = await _buildEntries(queue.items);
        if (generation != _playGeneration) return;
        // Взаимное исключение: старт аудио сам останавливает видео.
        await _videoPlayer.stop();
        if (generation != _playGeneration) return;
        _playlistToken = _currentToken;
        await _audioPlayer
            .loadPlaylist(entries, startIndex: index)
            .timeout(_loadTimeout);
        if (generation != _playGeneration) return;
        await _audioPlayer.play().timeout(_loadTimeout);
        if (generation != _playGeneration) return;
        if (resumeAt != null && resumeAt > Duration.zero) {
          await _audioPlayer.seek(resumeAt);
          if (generation != _playGeneration) return;
        }
        state = PlaybackState.playing(
          media: queue.items[index],
          type: MediaType.audio,
        );
      } else {
        await _playSingle(queue.items[index]);
        if (generation != _playGeneration) return;
      }
      _startProgressTimer();
      AppLogger.info('Queue started: index=$index of ${queue.items.length}');
    } finally {
      _loadingQueue = false;
    }
  }

  /// Открывает один трек (видео либо смешанная очередь) — плейлист mpv
  /// не используется, переход между треками остаётся поштучным.
  Future<void> _playSingle(Media media) async {
    final generation = _playGeneration;
    final entries = await _buildEntries([media]);
    if (generation != _playGeneration || entries.isEmpty) return;
    final entry = entries.first;
    _lastType = media.type;

    if (media.type == MediaType.audio) {
      await _videoPlayer.stop();
      await _audioPlayer
          .loadPlaylist([entry], startIndex: 0)
          .timeout(_loadTimeout);
      if (generation != _playGeneration) return;
      await _audioPlayer.play().timeout(_loadTimeout);
      if (generation != _playGeneration) return;
      state = PlaybackState.playing(media: media, type: MediaType.audio);
      return;
    }

    await _audioPlayer.stop();
    await _videoPlayer
        .open(entry.url, httpHeaders: entry.httpHeaders)
        .timeout(_loadTimeout);
    if (generation != _playGeneration) return;
    await _videoPlayer.play().timeout(_loadTimeout);
    if (generation != _playGeneration) return;

    _subscribeVideoStreams();

    // Загружаем сохранённую позицию для диалога resume (только видео).
    final resumePosition = await _loadSavedPosition(media.id);
    if (generation != _playGeneration) return;
    final saved = resumePosition != null && resumePosition > _resumeThreshold
        ? resumePosition
        : null;

    state = PlaybackState.playing(
      media: media,
      type: MediaType.video,
      savedPosition: saved,
    );

    if (resumePosition != null && resumePosition <= _resumeThreshold) {
      await _videoPlayer.seek(resumePosition);
    }
  }

  /// Готовит элементы плейлиста: локальный файл, если трек скачан,
  /// иначе URL потока с текущим токеном.
  Future<List<AudioQueueEntry>> _buildEntries(List<Media> items) async {
    final token = _currentToken;
    return await Future.wait(items.map((media) => _buildEntry(media, token)));
  }

  Future<AudioQueueEntry> _buildEntry(Media media, String? token) async {
    String? localPath;
    try {
      localPath = await ref
          .read(offlineCacheServiceProvider)
          .getLocalPath(media.id);
    } catch (e) {
      AppLogger.warn('Offline cache lookup failed for ${media.id}: $e');
    }
    final isLocal = localPath != null;
    return AudioQueueEntry(
      mediaId: media.id,
      url: localPath ?? '$_baseUrl/media/${media.id}/stream',
      title: media.title,
      artist: media.artists.isEmpty
          ? null
          : media.artists.map((a) => a.name).join(', '),
      artUri: isLocal ? null : _coverUrlFor(media),
      duration: media.duration != null
          ? Duration(seconds: media.duration!)
          : null,
      httpHeaders: (!isLocal && token != null)
          ? <String, String>{'Authorization': 'Bearer $token'}
          : null,
    );
  }

  String? _coverUrlFor(Media media) {
    if (media.coverUrl?.isNotEmpty ?? false) {
      return '$_baseUrl/media/${media.id}/cover';
    }
    if (media.thumbnailUrl?.isNotEmpty ?? false) {
      return '$_baseUrl/media/${media.id}/thumb';
    }
    return null;
  }

  String? get _currentToken => ref.read(settingsProvider).settings.authToken;

  /// mpv обновил токен в фоне (плановая проверка сессии, смена сервера):
  /// перезагружаем плейлист с новым Authorization, сохраняя позицию.
  void _onTokenChanged() {
    if (!_audioPlaylistActive) return;
    if (state is! PlaybackPlaying) return;
    final current = state as PlaybackPlaying;
    if (_playlistToken == _currentToken) return;
    final index = ref.read(playQueueProvider).currentIndex;
    AppLogger.info('Auth token changed, reloading queue at index $index');
    unawaited(
      _serialize(() => _startQueue(index, resumeAt: current.position))
          .catchError((Object e, StackTrace s) {
            AppLogger.error('Queue reload after token change failed', e, s);
          }),
    );
  }

  // --------------------------------------------------------------------------
  // Переходы внутри очереди
  // --------------------------------------------------------------------------

  /// Выполняет команду mpv внутри [_playChain] и переводит исключение в
  /// PlaybackState.error. `false` — команда не выполнилась.
  ///
  /// Проверка [_inPlaylistCommand] стоит ДО входа в [_playChain]: вложенный
  /// вызов приходит, пока уже выполняется команда mpv, и если сначала
  /// встать в очередь, получится взаимная блокировка (именно так выглядел
  /// исходный баг: datasource → handler.next() → onNext → очередь →
  /// next()). Флаг поднимается только на время выполнения команды, так
  /// что обычная вторая команда — второй тап по «вперёд» — приходит при
  /// опущенном флаге и просто встаёт в очередь.
  Future<bool> _playlistCommand(Future<void> Function() command) async {
    if (_inPlaylistCommand) {
      AppLogger.error(
        'Reentrant playlist command ignored',
        StateError('playlist command re-entered the coordinator'),
      );
      return false;
    }
    var done = false;
    try {
      await _serialize(() async {
        _inPlaylistCommand = true;
        try {
          await command();
          done = true;
        } finally {
          _inPlaylistCommand = false;
        }
      });
    } catch (e, s) {
      AppLogger.error('Playlist command failed', e, s);
      if (!_disposed) state = PlaybackState.error(message: e.toString());
    }
    return done;
  }

  @override
  Future<bool> next() async {
    if (!_audioPlaylistActive) return await _legacyNext();
    return await _playlistCommand(_audioPlayer.next);
  }

  @override
  Future<bool> previous() async {
    if (!_audioPlaylistActive) return await _legacyPrevious();
    return await _playlistCommand(_audioPlayer.previous);
  }

  @override
  Future<bool> jump(int index) async {
    final queue = ref.read(playQueueProvider);
    if (index < 0 || index >= queue.items.length) return false;
    if (!_audioPlaylistActive) {
      await _legacyJump(index);
      return true;
    }
    return await _playlistCommand(() => _audioPlayer.jump(index));
  }

  @override
  Future<void> removeAt(int index) async {
    final queue = ref.read(playQueueProvider);
    if (queue.items.isEmpty) {
      await stop();
      return;
    }
    if (_audioPlaylistActive) {
      await _playlistCommand(() => _audioPlayer.remove(index));
      return;
    }
    // Одиночный Media: mpv-плейлиста нет, пересобираем вручную.
    final current = state;
    final targetIndex = queue.currentIndex.clamp(0, queue.items.length - 1);
    final target = queue.items[targetIndex];
    if (current is PlaybackPlaying && current.media.id == target.id) return;
    await _playSingleMedia(target);
  }

  @override
  Future<void> restartCurrent() async {
    final queue = ref.read(playQueueProvider);
    final index = queue.currentIndex;
    if (index < 0 || index >= queue.items.length) return;
    if (_audioPlaylistActive) {
      await _playlistCommand(() async {
        await _audioPlayer.jump(index);
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
      });
      return;
    }
    await _playSingleMedia(queue.items[index]);
  }

  /// Переход поштучно — для видео и смешанных очередей, где mpv-плейлист
  /// не используется.
  Future<void> _playSingleMedia(Media media) async {
    try {
      await _serialize(() async {
        ++_playGeneration;
        state = const PlaybackState.loading();
        await _playSingle(media);
        _startProgressTimer();
      });
    } catch (e, s) {
      AppLogger.error('Single media play failed for ${media.id}', e, s);
      if (!_disposed) state = PlaybackState.error(message: e.toString());
      rethrow;
    }
  }

  Future<bool> _legacyNext() async {
    final queue = ref.read(playQueueProvider);
    final next = queue.currentIndex + 1;
    if (next >= queue.items.length) return false;
    await _guardedStart(next);
    return true;
  }

  Future<bool> _legacyPrevious() async {
    final queue = ref.read(playQueueProvider);
    final prev = queue.currentIndex - 1;
    if (prev < 0) return false;
    await _guardedStart(prev);
    return true;
  }

  Future<bool> _legacyJump(int index) async {
    await _guardedStart(index);
    return true;
  }

  /// mpv переключил элемент плейлиста (next/jump/удаление/авто-переход):
  /// индекс нужен очереди, а состояние UI — этому обработчику.
  void _onMpvPlaylistIndex(int index) {
    if (!_audioPlaylistActive) return;
    if (!_playlistIndexCtl.isClosed) _playlistIndexCtl.add(index);
    // Во время загрузки состояние выставит _startQueue; позиция и
    // длительность там ещё пустые.
    if (_loadingQueue || state is PlaybackLoading) return;

    final queue = ref.read(playQueueProvider);
    if (index < 0 || index >= queue.items.length) return;
    if (_lastType != MediaType.audio) return;
    final media = queue.items[index];
    if (state is PlaybackPlaying &&
        (state as PlaybackPlaying).media.id == media.id) {
      return;
    }
    // Удаление играющего последнего элемента в mpv (real.dart:504-528)
    // шлёт playing=false, completed=true и новый индекс одной пачкой. К этому
    // моменту очередь уже помечена завершённой, и воскрешать из неё Playing
    // нельзя — плеер стоит.
    if (state is PlaybackCompleted && !_lastPlayingSignal) return;
    state = PlaybackState.playing(
      media: media,
      type: MediaType.audio,
      isPaused: !_lastPlayingSignal,
    );
  }

  Future<void> _onCompleted(bool completed) async {
    if (!completed) return;
    final current = state;
    if (current is PlaybackPlaying && current.media.type == MediaType.video) {
      // Прогресс храним только для видео. НЕ ждём сохранение: сетевой
      // запрос (особенно в фоне/при слабой связи) блокировал бы
      // автопродвижение, и музыка «застревала» на конце трека. Гонки
      // completed:true vs completed:false нет: следующий трек стартует
      // из состояния loading, и _startQueue не сохраняет предыдущий
      // трек повторно.
      unawaited(
        _saveProgress(
          current.media.id,
          current.duration ?? current.position,
          current.duration ?? Duration.zero,
          completed: true,
        ),
      );
    }
    _cancelProgressTimer();

    // Пользователь переключил трек — EOF уже не нашего: игнорируем.
    if (state is PlaybackLoading) return;

    if (_audioPlaylistActive) {
      _onPlaylistCompleted();
      return;
    }
    await _advance();
  }

  /// EOF в режиме mpv-плейлиста.
  ///
  /// mpv поднят с `--keep-open=yes`, а это «Don't terminate if the current
  /// file is the last playlist entry»: при наличии следующего элемента
  /// mpv листает плейлист САМ (в mpv master опции playlist-auto-next уже
  /// нет, её роль поглощена keep-open; запретить авто-переход может только
  /// `--keep-open=always`). Поэтому индекс здесь двигать нельзя — Dart
  /// сдвинул бы его вторым разом и пропустил трек. Состояние обновит
  /// [_onMpvPlaylistIndex] по событию mpv.
  ///
  /// Действовать надо только когда очередь исчерпана: mpv остался на
  /// последнем элементе с `completed == true`.
  void _onPlaylistCompleted() {
    final queue = ref.read(playQueueProvider);
    final lastIndex = queue.items.length - 1;
    // Приоритет у индекса mpv: он переживает гонку порядка eof-reached и
    // START_FILE. Если EOF пришёл раньше авто-перехода, оба индекса ещё
    // старые и совпадают; если позже — mpv уже на новом элементе, а
    // Dart-овский currentIndex отстаёт.
    final mpvIndex = _audioPlayer.playlistIndex;
    final currentIndex = mpvIndex >= 0 ? mpvIndex : queue.currentIndex;
    if (currentIndex >= lastIndex) {
      state = const PlaybackState.completed();
      return;
    }
    AppLogger.info(
      'EOF at $currentIndex of $lastIndex — mpv advances the playlist',
    );
  }

  /// Поштучный переход для видео и смешанных очередей, где mpv-плейлист не
  /// используется и следующий трек надо открыть самим.
  Future<void> _advance() async {
    final queue = ref.read(playQueueProvider);
    if (!queue.hasNext) {
      state = const PlaybackState.completed();
      return;
    }
    // _startQueue сохраняет прогресс текущего видео, поэтому переводим в
    // loading до вызова: иначе сохранение повторилось бы вторым запросом
    // (completed:false поверх completed:true).
    state = const PlaybackState.loading();
    try {
      await ref.read(playQueueProvider.notifier).next();
    } catch (e, s) {
      AppLogger.error('Auto-advance failed', e, s);
      state = PlaybackState.error(message: e.toString());
    }
  }

  /// Handles player errors (e.g. 401, unreachable stream).
  void _onPlayerError(String error) {
    AppLogger.error('Player error: $error');
    if (state is PlaybackPlaying || state is PlaybackLoading) {
      state = PlaybackState.error(message: error);
    }
  }

  /// Handles buffering state changes.
  void _onBuffering(bool buffering) {
    // media_kit emits buffering events frequently; we don't want to
    // change state on every tick. The UI can subscribe to the stream
    // directly if it needs a buffering indicator.
  }

  /// Returns the saved watch position for [mediaId], or null if there is
  /// none (or the media was already completed).
  Future<Duration?> _loadSavedPosition(int mediaId) async {
    final result = await ref.read(mediaRepositoryProvider).getProgress();
    return await result.fold((_) async => null, (progressList) async {
      for (final p in progressList) {
        if (p.mediaId == mediaId && p.position > 0) {
          return Duration(seconds: p.position);
        }
      }
      return null;
    });
  }

  /// Saves watch progress to the backend. Best-effort: errors are logged
  /// and ignored. Отправляет duration и completed — бэкенд их принимает
  /// и сохраняет. Вызовы сериализуются через [_saveChain].
  Future<void> _saveProgress(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) {
    final result = _saveChain.then(
      (_) => _doSaveProgress(mediaId, position, duration, completed: completed),
    );
    _saveChain = result.catchError((_) {});
    return result;
  }

  Future<void> _doSaveProgress(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) async {
    if (position <= Duration.zero) return;
    try {
      await ref
          .read(mediaRepositoryProvider)
          .updateProgress(
            mediaId,
            position: position.inSeconds,
            duration: duration.inSeconds,
            completed: completed ?? false,
          );
    } on Exception catch (e) {
      developer.log('Failed to save progress: $e');
    }
  }

  /// Periodically persists watch progress while playing.
  void _startProgressTimer() {
    _cancelProgressTimer();
    _progressTimer = Timer.periodic(_progressSaveInterval, (_) {
      final current = state;
      // Периодическое сохранение — только для видео.
      if (current is PlaybackPlaying &&
          !current.isPaused &&
          current.media.type == MediaType.video) {
        unawaited(
          _saveProgress(
            current.media.id,
            current.position,
            current.duration ?? Duration.zero,
          ),
        );
      }
    });
  }

  Future<void> pause() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.pause();
      } else {
        await _videoPlayer.pause();
      }
      state = current.copyWith(isPaused: true);
      if (current.media.type == MediaType.video) {
        await _saveProgress(
          current.media.id,
          current.position,
          current.duration ?? Duration.zero,
        );
      }
    }
  }

  Future<void> resume() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.play();
      } else {
        await _videoPlayer.play();
      }
      state = current.copyWith(isPaused: false);
    }
  }

  Future<void> seek(Duration position) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.seek(position);
      } else {
        await _videoPlayer.seek(position);
      }
    }
  }

  /// Sets playback speed (video only).
  Future<void> setSpeed(double speed) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.video) {
        await _videoPlayer.setRate(speed);
        state = current.copyWith(speed: speed);
      }
    }
  }

  /// Seeks to the saved position (from the resume dialog).
  Future<void> seekToSavedPosition() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      final saved = current.savedPosition;
      if (saved != null) {
        await _videoPlayer.seek(saved);
        state = current.copyWith(savedPosition: null);
      }
    }
  }

  /// Starts playback from the beginning (from the resume dialog).
  Future<void> startFromBeginning() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _videoPlayer.seek(Duration.zero);
      state = current.copyWith(savedPosition: null);
    }
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  @override
  Future<void> stop() async {
    // Прерываем незавершённые операции: начатая загрузка на ближайшей
    // проверке поколения выйдет и не запустит воспроизведение после stop.
    _playGeneration++;
    _cancelProgressTimer();
    _audioPlaylistActive = false;
    _playlistToken = null;
    // Сбрасываем и playing-сигнал: после stop() движок пришлёт playing:false
    // сам, но полагаться на порядок событий при смене сессии не нужно —
    // иначе устаревшее true утечёт в isPaused следующего цикла.
    // В _startQueue сброс не требуется: engine.open() успевает прислать
    // playing:true, пока _loadingQueue ещё держит события индекса.
    _lastPlayingSignal = false;
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.video) {
        await _saveProgress(
          current.media.id,
          current.position,
          current.duration ?? Duration.zero,
        );
      }
    }
    // Останавливаем физический плеер независимо от состояния (в т.ч.
    // loading/completed): при loading видео уже может играть после open(),
    // а при completed аудио нужно убрать системное уведомление.
    switch (_lastType) {
      case MediaType.audio:
        await _audioPlayer.stop();
      case MediaType.video:
        await _videoPlayer.stop();
      case MediaType.unknown:
      case null:
        break;
    }
    _lastType = null;
    state = const PlaybackState.initial();
  }

  Future<void> reset() async {
    await stop();
  }
}

/// Provider for the audio handler (initialized in main.dart via
/// AudioService.init).
final audioHandlerProvider = Provider<FluxAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in main()');
});

/// Provider for audio player datasource.
final audioPlayerDatasourceProvider = Provider<AudioPlaybackSource>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final ds = AudioPlayerDatasource(handler);
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for video player datasource.
/// NOT autoDispose: the PlaybackCoordinator holds it via ref.read across
/// multiple await points. If it were autoDispose, the player could be
/// disposed and recreated between open() and play(), causing operations
/// on different player instances.
final videoPlayerDatasourceProvider = Provider<VideoPlaybackSource>((ref) {
  final ds = VideoPlayerDatasource();
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for playback coordinator.
final playbackCoordinatorProvider =
    NotifierProvider<PlaybackCoordinator, PlaybackState>(
      PlaybackCoordinator.new,
    );

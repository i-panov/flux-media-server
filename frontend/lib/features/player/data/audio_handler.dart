import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/player/data/audio_engine.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Загрузчик обложки трека: возвращает локальный файл или `null`.
///
/// Живёт рядом с хендлером, а не в audio_engine.dart: обложка нужна для
/// MediaItem системного уведомления, к движку отношения не имеет. Тип
/// вынесен, чтобы тесты подменяли сеть — инвариант «в критическом пути
/// перехода сети нет» проверяется без реального HTTP.
typedef ArtworkFetcher = Future<File?> Function(
  String url,
  Map<String, String>? httpHeaders,
);

/// Audio handler that wraps an [AudioEngine] (media_kit's `Player` по
/// умолчанию) and integrates with the system media notification, lock
/// screen controls, and background audio playback via `audio_service`.
///
/// Плейлист живёт в mpv (`engine.open(Playlist(...))`): переход между
/// треками — одна mpv-команда, без переоткрытия URL, повторного резолва
/// токена и сетевых запросов в критическом пути.
///
/// Команды mpv ([next], [previous], [jump]) и команды системного
/// уведомления ([skipToNext], [skipToPrevious]) — разные пути: первым
/// пользуется координатор, вторым audio_service. Смешивать их нельзя,
/// иначе координатор, вызывающий next() из _onCompleted, попал бы в
/// onNext → очередь → next() и намертво заблокировал бы цепочку
/// запусков. Разделение проверяется тестами в audio_handler_test.dart.
///
/// [engine] и [artworkFetcher] внедряются только для тестов: настоящий
/// media_kit `Player` тянет libmpv через dlopen и недоступен в
/// `flutter test`.
class FluxAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements AudioPlaybackSource {
  new({AudioEngine? engine, this._artworkFetcher})
    : engine = engine ?? MediaKitAudioEngine(player: Player()) {
    unawaited(_init());
  }

  /// Движок воспроизведения: mpv-плеер или его подмена в тестах.
  final AudioEngine engine;

  /// Callbacks wired up from the play queue by `main.dart`.
  Future<bool> Function()? onNext;
  Future<bool> Function()? onPrevious;
  void Function()? onToggleFavorite;

  /// Делегат для play из системного уведомления. Маршрутизируется через
  /// координатор (см. main.dart), чтобы состояние UI не расходилось с
  /// реальным воспроизведением (например, play после completed должен
  /// перезапускать трек, а не играть «в фоне» с состоянием completed).
  Future<void> Function()? onPlay;

  /// Whether the current track is favorited (for notification icon).
  bool isFavorite = false;

  /// Сколько обложек держим на диске. Обложка каждого трека качается
  /// отдельно (audio_service не шлёт Authorization) и кешируется по
  /// mediaId, поэтому лимит нужен, чтобы каталог не рос на всю сессию:
  /// на 7-м distinct-треке [_pruneArtwork] вытесняет самый старый файл.
  static const _maxCachedArtwork = 6;

  static const _artTimeout = Duration(seconds: 10);

  /// Потолок ожидания стартовой уборки обложек. Уборка идёт по локальному
  /// каталогу и обычно занимает миллисекунды; грейс ограничивает ущерб,
  /// если `getTemporaryDirectory()` или перечисление каталога зависнут. На
  /// воспроизведение не влияет — обложка всюду грузится через unawaited.
  ///
  /// Гонку с [_cleanupStaleArtwork] при истечении грейса снимает отсев по
  /// времени изменения в [_startedAt], а не сам грейс.
  static const _artCleanupGrace = Duration(seconds: 3);

  /// Загрузчик обложки; null — используется HTTP с auth-заголовками.
  final ArtworkFetcher? _artworkFetcher;

  /// Завершается, когда [_cleanupStaleArtwork] закончит проход. Нужен,
  /// чтобы уборка не удалила файл обложки, который уже скачали и на
  /// который уже ссылается [_artCache].
  final Completer<void> _artCleanupDone = Completer<void>();

  /// Момент создания хендлера. Всё `flux_art_*` новее него — наши
  /// собственные файлы (пишутся прямо сейчас либо уже в [_artCache]),
  /// и [_cleanupStaleArtwork] их не трогает.
  final DateTime _startedAt = DateTime.now();

  /// Плейлист, синхронизированный с mpv по индексу. mpv знает только
  /// uri, поэтому метаданные для уведомления храним здесь.
  List<AudioQueueEntry> _entries = const [];

  /// Кеш скачанных обложек: mediaId -> file:// uri. Вставка упорядочена,
  /// поэтому первым вытесняется самый старый.
  final Map<int, Uri> _artCache = {};

  /// mediaId обложек, которые уже запрошены, но ещё не долетели. Заполняется
  /// синхронно до первого await: стартовый трек зовёт [_loadArtworkFor] и из
  /// слушателя `engine.playlistStream` (он срабатывает внутри
  /// `await engine.open(...)`), и явно — а без этого флага оба вызова
  /// прошли бы проверку кеша и сделали по два HTTP GET в один файл.
  final Set<int> _artInFlight = {};

  final StreamController<int> _playlistIndexCtl =
      StreamController<int>.broadcast();

  int _index = -1;

  /// Играл ли трек до прерывания (звонок и т.п.) — для resume.
  bool _wasPlayingBeforeInterruption = false;

  StreamSubscription<dynamic>? _interruptionSub;
  StreamSubscription<dynamic>? _noisySub;

  static const List<MediaControl> _controlsPlaying = [
    MediaControl.skipToPrevious,
    MediaControl.pause,
    MediaControl.skipToNext,
  ];

  static const List<MediaControl> _controlsPaused = [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.skipToNext,
  ];

  Future<void> _init() async {
    // Подписки на потоки media_kit делаем синхронно и первыми: они
    // привязаны к engine, и их нельзя терять из-за await на
    // платформенном канале (AudioSession инициализируется асинхронно).
    _subscribePlayerStreams();
    // Уборку запускаем до AudioSession: [_artCleanupDone] завершается в
    // её finally, и каждая загрузка обложки его ждёт. Если бы AudioSession
    // подвисла, уборка не началась бы вовсе и каждая обложка ждала бы
    // завершения зря.
    unawaited(_cleanupStaleArtwork());
    await _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    // Аудиофокус: пауза при звонках/других приложениях, пауза при
    // отключении наушников (becomingNoisy).
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSub = session.interruptionEventStream.listen((event) {
        // duck (тихое пересечение с другим приложением) — НЕ прерываем
        // плеер: раньше begin=true ставил паузу на любой тип события, а
        // возобновление шло только для pause, из-за чего после duck
        // музыка не возвращалась никогда.
        if (event.begin && event.type == AudioInterruptionType.duck) return;
        if (event.begin) {
          _wasPlayingBeforeInterruption = engine.isPlaying;
          if (_wasPlayingBeforeInterruption) unawaited(engine.pause());
          return;
        }
        if (_wasPlayingBeforeInterruption) {
          _wasPlayingBeforeInterruption = false;
          unawaited(engine.play());
        }
      });
      _noisySub = session.becomingNoisyEventStream.listen(
        (_) => engine.pause(),
      );
    } catch (e) {
      // audio_session может быть недоступен на некоторых платформах —
      // воспроизведение продолжает работать без обработки фокуса.
      AppLogger.error('AudioSession init failed', e);
    }
  }

  void _subscribePlayerStreams() {
    engine.playingStream.listen((playing) {
      final controls = playing ? _controlsPlaying : _controlsPaused;
      final state = playbackState.value.copyWith(
        playing: playing,
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        processingState: AudioProcessingState.ready,
      );
      playbackState.add(state);
    });

    engine.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });

    engine.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });

    engine.completedStream.listen((completed) {
      if (completed) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.completed,
          ),
        );
      }
    });

    // mpv сам переключает элемент плейлиста: обновляем метаданные
    // уведомления и индекс для координатора.
    engine.playlistStream.listen((playlist) {
      final index = playlist.index;
      if (index < 0 || index >= _entries.length) return;
      if (index != _index) {
        _index = index;
        _publishIndex(index);
      }
      // Метаданные обновляем и при неизменном индексе: удаление элемента
      // сдвигает содержимое, и если судить только по индексу, уведомление
      // продолжило бы показывать уже удалённый трек. _updateMediaItem
      // сам отсекает пустые обновления.
      _updateMediaItem(index);
      unawaited(_loadArtworkFor(index));
    });
  }

  void _publishIndex(int index) {
    if (_playlistIndexCtl.isClosed) return;
    _playlistIndexCtl.add(index);
  }

  /// Загружает [entries] в mpv как единый плейлист и стартует с
  /// [startIndex]. Никаких сетевых запросов здесь нет намеренно.
  @override
  Future<void> loadPlaylist(
    List<AudioQueueEntry> entries, {
    required int startIndex,
  }) async {
    if (entries.isEmpty) return;
    _entries = List.unmodifiable(entries);
    _index = -1;
    await activateSession();
    // Стартовый MediaItem — сразу, чтобы уведомление не ждало обложку.
    _updateMediaItem(startIndex);
    await engine.open(
      Playlist([
        // Сильные ссылки на Media держит сам media_kit (current) —
        // без них Media.cache вытесняется финализатором, и mpv теряет
        // httpHeaders (Authorization) для этого uri.
        for (final entry in entries)
          Media(entry.url, httpHeaders: entry.httpHeaders),
      ], index: startIndex),
    );
    unawaited(_loadArtworkFor(startIndex));
  }

  @override
  Future<void> appendToPlaylist(List<AudioQueueEntry> entries) async {
    if (entries.isEmpty) return;
    _entries = [..._entries, ...entries];
    for (final entry in entries) {
      // player.add держит сильную ссылку на Media — без неё
      // Media.cache вытесняется финализатором и mpv теряет httpHeaders
      // (Authorization) для этого uri.
      await engine.add(Media(entry.url, httpHeaders: entry.httpHeaders));
    }
  }

  /// Следующий элемент плейлиста — чистая mpv-команда.
  /// Команда из системного уведомления идёт отдельным путём, см.
  /// [skipToNext]: смешивать их нельзя, иначе координатор, вызывающий
  /// next() из _onCompleted, попал бы в onNext -> очередь -> next() и
  /// намертво заблокировал бы _playChain.
  @override
  Future<void> next() => engine.next();

  @override
  Future<void> previous() => engine.previous();

  /// Команда «следующий трек» из системного уведомления, лок-скрина,
  /// гарнитуры и медиаклавиш. audio_service маршрутизирует
  /// MediaAction.skipToNext именно сюда (audio_service.dart:2539),
  /// в BaseAudioHandler.skipToNext() — пустая заглушка.
  @override
  Future<void> skipToNext() async {
    await onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onPrevious?.call();
  }

  @override
  Future<void> jump(int index) => engine.jump(index);

  /// Удаляет элемент плейлиста. Метаданные [_entries] приводим в
  /// соответствие ДО вызова mpv: событие stream.playlist приходит по
  /// mpv-индексу, и при рассинхроне в уведомлении показались бы данные
  /// соседнего трека.
  @override
  Future<void> remove(int index) async {
    if (index < 0 || index >= _entries.length) return;
    _entries = List<AudioQueueEntry>.from(_entries)..removeAt(index);
    await engine.remove(index);
  }

  @override
  int get playlistIndex => _index;

  @override
  Stream<int> get playlistIndexStream => _playlistIndexCtl.stream;

  /// Запрашивает аудиофокус. Без него Android не присылает
  /// прерывания, а другие приложения могут играть поверх нас.
  Future<void> activateSession() async {
    try {
      await (await AudioSession.instance).setActive(true);
    } catch (e) {
      AppLogger.warn('AudioSession.activate failed: $e');
    }
  }

  Future<void> _deactivateSession() async {
    try {
      await (await AudioSession.instance).setActive(false);
    } catch (e) {
      AppLogger.warn('AudioSession.deactivate failed: $e');
    }
  }

  void _updateMediaItem(int index) {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    final artUri = _artCache[entry.mediaId];
    final prev = mediaItem.value;
    if (prev != null &&
        prev.id == entry.url &&
        prev.artUri == artUri &&
        prev.duration == entry.duration) {
      return;
    }
    mediaItem.add(
      MediaItem(
        id: entry.url,
        title: entry.title,
        artist: entry.artist,
        artUri: artUri,
        duration: entry.duration,
      ),
    );
  }

  /// Скачивает обложку трека (в фоне) и обновляет уведомление.
  ///
  /// Вне критического пути: вызывается через unawaited и никогда не
  /// блокирует запуск очередной записи. Перед скачиванием дожидается
  /// стартовой уборки, иначе та может удалить файл, на который уже
  /// ссылается [_artCache].
  Future<void> _loadArtworkFor(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    // Кеш, отсутствие обложки и «уже в полёте» проверяем ДО любого await:
    // слушатель плейлиста зовёт это на каждое событие, и проверка должна
    // быть синхронной, иначе два вызова на одном треке обойдут её.
    if (_artCache.containsKey(entry.mediaId)) {
      _updateMediaItem(index);
      return;
    }
    final artUri = entry.artUri;
    if (artUri == null) return;
    if (!_artInFlight.add(entry.mediaId)) return;
    try {
      // Уборка прошлой сессии должна закончиться до скачивания, иначе она
      // удалит только что записанный файл, на который уже ссылается кеш.
      // Грейс ограничивает ожидание на случай зависшего канала: обложка
      // опаздывает, но воспроизведение не страдает.
      await _artCleanupDone.future.timeout(_artCleanupGrace, onTimeout: () {});
      if (!_entries.any((e) => e.mediaId == entry.mediaId)) return;
      final file = await _downloadArtwork(artUri, entry.httpHeaders);
      if (file == null) return;
      _artCache[entry.mediaId] = file.uri;
      unawaited(_pruneArtwork());
      // Если пользователь уже ушёл на другой трек — уведомление не трогаем.
      if (_index == index) _updateMediaItem(index);
    } finally {
      _artInFlight.remove(entry.mediaId);
    }
  }

  /// Downloads [artUri] with auth headers to a temp file.
  /// Falls back to null on failure — обложка не критична.
  ///
  /// При внедрённом [_artworkFetcher] сеть не используется вовсе.
  Future<File?> _downloadArtwork(
    String artUri,
    Map<String, String>? httpHeaders,
  ) async {
    final injected = _artworkFetcher;
    if (injected != null) return await injected(artUri, httpHeaders);

    final uri = Uri.tryParse(artUri);
    if (uri == null || !uri.scheme.startsWith('http')) return null;

    try {
      final response = await http
          .get(uri, headers: httpHeaders ?? {})
          .timeout(_artTimeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_artFileName(uri)}');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (e) {
      AppLogger.warn('Artwork download failed: $e');
      return null;
    }
  }

  String _artFileName(Uri uri) {
    final hash = uri.toString().hashCode.abs().toRadixString(16);
    return 'flux_art_${uri.pathSegments.last}_$hash.jpg';
  }

  /// Вытесняет самые старые обложки, чтобы не раздувать кеш.
  Future<void> _pruneArtwork() async {
    while (_artCache.length > _maxCachedArtwork) {
      final oldest = _artCache.keys.first;
      final uri = _artCache.remove(oldest);
      if (uri == null) continue;
      try {
        await File.fromUri(uri).delete();
      } catch (_) {
        // Не критично — мусор удалится при следующем запуске.
      }
    }
  }

  /// Одноразовая уборка обложек, оставшихся от прошлых сессий.
  ///
  /// На старте [_artCache] пуст, поэтому сносятся все `flux_art_*` из
  /// временного каталога: кеш живёт ровно одну сессию, а [_pruneArtwork]
  /// держит его в пределах [_maxCachedArtwork] файлов.
  ///
  /// Файлы новее [_startedAt] не трогаем: это наши собственные обложки —
  /// либо пишутся прямо сейчас, либо уже в [_artCache]. Так уборка остаётся
  /// безопасной даже если [_loadArtworkFor] не дождался её из-за
  /// [_artCleanupGrace] и пошёл качать параллельно.
  Future<void> _cleanupStaleArtwork() async {
    try {
      final dir = await getTemporaryDirectory();
      final known = _artCache.values.map((uri) => uri.path).toSet();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('flux_art_') || known.contains(entity.path)) {
          continue;
        }
        if (entity.lastModifiedSync().isAfter(_startedAt)) continue;
        await entity.delete();
      }
    } catch (e) {
      AppLogger.warn('Artwork cleanup failed: $e');
    } finally {
      // Снимает ожидание, если проход завершился — с ошибкой или без.
      // При НАСТОЯЩЕМ зависании канала finally не выполняется: тогда
      // ожидание снимает [_artCleanupGrace] в _loadArtworkFor, а при
      // уничтожении хендлера — dispose().
      if (!_artCleanupDone.isCompleted) _artCleanupDone.complete();
    }
  }

  /// Программный запуск воспроизведения — для координатора
  /// ([AudioPlaybackSource.play]). В отличие от [play] НЕ маршрутизирует в
  /// [onPlay]: координатор и так пришёл из состояния, а делегат уводит в
  /// [onPlay] → координатор.resume() → play() → onPlay, то есть в
  /// бесконечную рекурсию (а из loading он не делает вообще ничего, и
  /// воспроизведение не стартует).
  Future<void> playDirect() => engine.play();

  /// Контракт `audio_service`: команда play из системного уведомления,
  /// лок-скрина, гарнитуры и медиаклавиш. Маршрутизируется через
  /// координатор, чтобы состояние UI не расходилось с реальным
  /// воспроизведением (например, play после completed должен перезапускать
  /// трек, а не играть «в фоне» с состоянием completed).
  @override
  Future<void> play() async {
    if (onPlay != null) {
      await onPlay!();
    } else {
      await activateSession();
      await engine.play();
    }
  }

  @override
  Future<void> pause() async {
    await engine.pause();
  }

  @override
  Future<void> stop() async {
    _wasPlayingBeforeInterruption = false;
    await engine.stop();
    _entries = const [];
    _index = -1;
    await _deactivateSession();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await engine.seek(position);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'toggleFavorite') {
      onToggleFavorite?.call();
      return;
    }
    return await super.customAction(name, extras);
  }

  @override
  Future<void> setVolume(double volume) => engine.setVolume(volume);

  @override
  Stream<double> get volumeStream => engine.volumeStream;

  @override
  double get volume => engine.volume;

  @override
  Stream<Duration> get positionStream => engine.positionStream;

  @override
  Stream<Duration> get durationStream => engine.durationStream;

  @override
  Stream<bool> get playingStream => engine.playingStream;

  @override
  Stream<bool> get completedStream => engine.completedStream;

  @override
  Stream<String> get errorStream => engine.errorStream;

  @override
  Stream<bool> get bufferingStream => engine.bufferingStream;

  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _playlistIndexCtl.close();
    // Снимаем ожидание зависших загрузок обложек: хендлер уничтожен, и
    // держать их фьючи незавершёнными незачем.
    if (!_artCleanupDone.isCompleted) _artCleanupDone.complete();
    await engine.dispose();
  }
}

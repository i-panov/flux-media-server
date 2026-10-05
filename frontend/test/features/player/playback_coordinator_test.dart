import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';
import 'package:media_kit/media_kit.dart' hide Media;

Media _media(int id, MediaType type) =>
    Media(id: id, title: 'Media $id', year: 2024, type: type, fileSize: 1024);

/// Settles all pending microtasks and short futures.
Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Фейк аудиоплеера поверх mpv-плейлиста: повторяет поведение media_kit —
/// next/jump/remove двигают индекс и эмитят его в playlistIndexStream,
/// а loadPlaylist полностью переоткрывает плейлист.
class _FakeAudioSource implements AudioPlaybackSource {
  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();
  final errorCtl = StreamController<String>.broadcast();
  final bufferingCtl = StreamController<bool>.broadcast();
  final volumeCtl = StreamController<double>.broadcast();
  final indexCtl = StreamController<int>.broadcast();

  /// Текущий плейлист mpv.
  final List<AudioQueueEntry> playlist = [];

  int loadSourceCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int seekCalls = 0;
  int setVolumeCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int jumpCalls = 0;
  int removeCalls = 0;
  @override
  double volume = 100;
  final List<String> openedUrls = [];
  final List<int> jumpTargets = [];
  final List<int> removedIndexes = [];
  final List<Duration> seeks = [];

  /// Когда задан, loadPlaylist() ждёт его — для эмуляции долгой загрузки.
  Completer<void>? loadGate;

  /// Если задан, loadPlaylist() бросает его.
  Object? loadError;

  /// Вызывается изнутри next()/jump(): имитирует ошибочную маршрутизацию,
  /// при которой команда mpv возвращается в координатор (регрессия на
  /// FluxAudioHandler.next() -> onNext -> queue.next() -> next()).
  Future<void> Function()? onInsideCommand;

  int _index = -1;

  @override
  int get playlistIndex => _index;

  @override
  Stream<int> get playlistIndexStream => indexCtl.stream;

  @override
  Future<void> loadPlaylist(
    List<AudioQueueEntry> entries, {
    required int startIndex,
  }) async {
    if (loadGate != null) await loadGate!.future;
    final error = loadError;
    if (error != null) throw Exception(error);
    loadSourceCalls++;
    playlist
      ..clear()
      ..addAll(entries);
    openedUrls
      ..clear()
      ..addAll(entries.map((e) => e.url));
    // Порядок повторяет media_kit real.dart:137-233 (open с play:true):
    // сначала внутренний stop(open: true) -> playing:false, затем выход
    // из паузы -> playing:true, и ПОСЛЕДНИМ шагом playlist-pos -> индекс.
    // Индекс обязан приходить после playing:true, иначе координатор
    // запишет isPaused в состояние, которое в mpv недостижимо.
    if (!playingCtl.isClosed) playingCtl.add(false);
    if (!playingCtl.isClosed) playingCtl.add(true);
    _emitIndex(startIndex);
  }

  @override
  Future<void> appendToPlaylist(List<AudioQueueEntry> entries) async {
    playlist.addAll(entries);
  }

  @override
  Future<void> next() async {
    nextCalls++;
    await onInsideCommand?.call();
    if (_index + 1 < playlist.length) _emitIndex(_index + 1);
  }

  @override
  Future<void> previous() async {
    previousCalls++;
    await onInsideCommand?.call();
    if (_index > 0) _emitIndex(_index - 1);
  }

  @override
  Future<void> jump(int index) async {
    jumpCalls++;
    jumpTargets.add(index);
    await onInsideCommand?.call();
    _emitIndex(index);
  }

  @override
  Future<void> remove(int index) async {
    removeCalls++;
    removedIndexes.add(index);
    if (index < 0 || index >= playlist.length) return;
    final isPlayingLast = _index == index && playlist.length - 1 == index;
    // Правило media_kit (real.dart:551-554): индекс уменьшается, только
    // если текущий БОЛЬШЕ удаляемого, иначе остаётся прежним.
    final current = _index;
    playlist.removeAt(index);
    if (playlist.isEmpty) return;
    var target = current > index ? current - 1 : current;
    if (isPlayingLast) {
      // Отдельная ветка media_kit (real.dart:504-528): индекс уезжает на
      // length-2, воспроизведение встаёт и приходит синтетический EOF.
      // Порядок тот же, что при доигрывании: сначала playing, потом
      // completed, потом новый индекс.
      target = playlist.length - 1;
      playingCtl.add(false);
      completedCtl.add(true);
    }
    _emitIndex(target.clamp(0, playlist.length - 1));
  }

  void _emitIndex(int index) {
    _index = index;
    if (indexCtl.isClosed) return;
    // mpv присылает индекс асинхронно, отдельным событием.
    scheduleMicrotask(() {
      if (!indexCtl.isClosed) indexCtl.add(index);
    });
  }

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    seeks.add(position);
  }

  @override
  Future<void> setVolume(double volume) async => setVolumeCalls++;

  @override
  Stream<Duration> get positionStream => positionCtl.stream;

  @override
  Stream<Duration> get durationStream => durationCtl.stream;

  @override
  Stream<bool> get playingStream => playingCtl.stream;

  @override
  Stream<bool> get completedStream => completedCtl.stream;

  @override
  Stream<String> get errorStream => errorCtl.stream;

  @override
  Stream<bool> get bufferingStream => bufferingCtl.stream;

  @override
  Stream<double> get volumeStream => volumeCtl.stream;

  /// EOF повторяет поведение mpv с `--keep-open=yes`: следующий элемент
  /// плейлиста включается САМ (mpv master: yes = «Don't terminate if the
  /// current file is the last playlist entry», то есть при наличии
  /// следующего он листается сам), а событие completed приходит следом.
  ///
  /// [autoAdvanceOnEof] выключается в тестах, где продвижение не
  /// должно происходить (например, проверка guard'а на PlaybackLoading).
  bool autoAdvanceOnEof = true;

  /// Порядок событий повторяет mpv: на EOF сначала приходит
  /// `eof-reached` (completed), и только потом mpv стартует следующий
  /// файл — `playlist-playing-pos` меняется после. Индекс тоже
  /// обновляется асинхронно, как у mpv, поэтому в момент completed
  /// координатор видит старый индекс.
  void emitCompleted() {
    completedCtl.add(true);
    if (autoAdvanceOnEof && _index + 1 < playlist.length) {
      final next = _index + 1;
      scheduleMicrotask(() {
        if (indexCtl.isClosed) return;
        _index = next;
        indexCtl.add(next);
      });
    }
  }

  void disposeStreams() {
    for (final c in [
      positionCtl,
      durationCtl,
      playingCtl,
      completedCtl,
      errorCtl,
      bufferingCtl,
      volumeCtl,
      indexCtl,
    ]) {
      unawaited(c.close());
    }
  }
}

class _FakeVideoSource implements VideoPlaybackSource {
  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();
  final errorCtl = StreamController<String>.broadcast();
  final bufferingCtl = StreamController<bool>.broadcast();
  final rateCtl = StreamController<double>.broadcast();

  int openCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int setRateCalls = 0;
  final List<Duration> seekCalls = [];
  final List<String> openedUrls = [];
  @override
  double rate = 1;
  @override
  Duration position = Duration.zero;

  /// Когда задан, open() ждёт его — для эмуляции длительной загрузки.
  Completer<void>? openGate;

  /// Если задан, open() бросает его.
  Object? openError;

  @override
  Player get player => throw UnimplementedError();

  @override
  Future<void> open(String url, {Map<String, String>? httpHeaders}) async {
    if (openGate != null) await openGate!.future;
    final error = openError;
    if (error != null) throw Exception(error);
    openCalls++;
    openedUrls.add(url);
  }

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> seek(Duration position) async => seekCalls.add(position);

  @override
  Future<void> setRate(double rate) async {
    setRateCalls++;
    this.rate = rate;
    rateCtl.add(rate);
  }

  @override
  Stream<Duration> get positionStream => positionCtl.stream;

  @override
  Stream<Duration> get durationStream => durationCtl.stream;

  @override
  Stream<bool> get playingStream => playingCtl.stream;

  @override
  Stream<bool> get completedStream => completedCtl.stream;

  @override
  Stream<String> get errorStream => errorCtl.stream;

  @override
  Stream<bool> get bufferingStream => bufferingCtl.stream;

  @override
  Stream<double> get rateStream => rateCtl.stream;

  void disposeStreams() {
    for (final c in [
      positionCtl,
      durationCtl,
      playingCtl,
      completedCtl,
      errorCtl,
      bufferingCtl,
      rateCtl,
    ]) {
      unawaited(c.close());
    }
  }
}

class _FakeMediaRepository implements MediaRepository {
  List<WatchProgress> progress = [];

  /// (mediaId, position, duration, completed) в порядке вызовов.
  final List<({int mediaId, int position, int duration, bool? completed})>
  updates = [];

  /// Когда задан, updateProgress() ждёт его — для эмуляции медленной сети.
  Completer<void>? progressGate;

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
      Right(progress);

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async {
    if (progressGate != null) await progressGate!.future;
    updates.add((
      mediaId: mediaId,
      position: position ?? 0,
      duration: duration ?? 0,
      completed: completed,
    ));
    return Right(
      WatchProgress(
        userId: 1,
        mediaId: mediaId,
        position: position ?? 0,
        duration: duration ?? 0,
        completed: completed ?? false,
      ),
    );
  }

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
  checkHash(String hash) => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> deleteMedia(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<Artist>>> getArtists() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Artist>> updateArtistName(
    int artistId,
    String name,
  ) async => const Left(ServerFailure());

  @override
  Future<Either<Failure, void>> uploadArtistCover(
    int artistId,
    String filePath, {
    bool Function()? isCancelled,
  }) async => const Left(ServerFailure());

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, UploadStatus>> getUploadStatus(int jobId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> cancelUpload(int jobId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<Media>>> getMediaBulk(List<int> ids) =>
      throw UnimplementedError();
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  Future<void> clearAuthToken() async {}

  @override
  Future<void> clearRefreshToken() async {}

  @override
  Future<void> setAuthToken(String token) async {}

  @override
  Future<void> setRefreshToken(String token) async {}

  @override
  Future<void> setServerUrl(String url) async {}

  @override
  String getLocale() => 'ru';

  @override
  Future<void> setLocale(String locale) async {}
}

class _FakeOfflineCache extends OfflineCacheService {
  new(super.ref, super.baseUrl);

  @override
  Future<String?> getLocalPath(int mediaId) async => null;
}

void main() {
  late _FakeAudioSource audio;
  late _FakeVideoSource video;
  late _FakeMediaRepository repo;
  late ProviderContainer container;
  late PlaybackCoordinator coordinator;
  late PlayQueueNotifier queue;

  setUp(() async {
    audio = _FakeAudioSource();
    video = _FakeVideoSource();
    repo = _FakeMediaRepository();
    container = ProviderContainer(
      overrides: [
        audioPlayerDatasourceProvider.overrideWithValue(audio),
        baseUrlProvider.overrideWithValue('http://test/api'),
        playbackCoordinatorProvider.overrideWith(PlaybackCoordinator.new),
        videoPlayerDatasourceProvider.overrideWithValue(video),
        mediaRepositoryProvider.overrideWithValue(repo),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        offlineCacheServiceProvider.overrideWith(
          (ref) => _FakeOfflineCache(ref, 'http://test/api'),
        ),
      ],
    );
    coordinator = container.read(playbackCoordinatorProvider.notifier);
    queue = container.read(playQueueProvider.notifier);
    await container.read(settingsProvider.notifier).init();
    addTearDown(() {
      container.dispose();
      audio.disposeStreams();
      video.disposeStreams();
    });
  });

  PlaybackState readState() => container.read(playbackCoordinatorProvider);

  /// Отдельный контейнер с произвольным кешем офлайн-файлов.
  ProviderContainer containerWithCache(
    OfflineCacheService Function(Ref ref) build,
  ) => ProviderContainer(
    overrides: [
      audioPlayerDatasourceProvider.overrideWithValue(audio),
      baseUrlProvider.overrideWithValue('http://test/api'),
      playbackCoordinatorProvider.overrideWith(PlaybackCoordinator.new),
      videoPlayerDatasourceProvider.overrideWithValue(video),
      mediaRepositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      offlineCacheServiceProvider.overrideWith(build),
    ],
  );

  group('PlaybackCoordinator queue start', () {
    test('starts audio playback as a single mpv playlist', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);

      expect(readState(), isA<PlaybackPlaying>());
      expect((readState() as PlaybackPlaying).type, MediaType.audio);
      // Один вызов loadPlaylist на всю очередь: mpv сам переключает треки,
      // поэтому переход не переоткрывает URL и не трогает сеть.
      expect(audio.loadSourceCalls, 1);
      expect(audio.playCalls, 1);
      expect(audio.playlist.map((e) => e.url), [
        'http://test/api/media/1/stream',
        'http://test/api/media/2/stream',
      ]);
    });

    test('starts video playback and sets playing state', () async {
      await queue.setQueue([_media(1, MediaType.video)]);

      expect(readState(), isA<PlaybackPlaying>());
      expect((readState() as PlaybackPlaying).type, MediaType.video);
      expect(video.openCalls, 1);
      expect(video.playCalls, 1);
    });

    test('concurrent setQueue calls serialize, the last queue wins', () async {
      final f1 = queue.setQueue([_media(1, MediaType.video)]);
      final f2 = queue.setQueue([_media(2, MediaType.video)]);
      await Future.wait([f1, f2]);
      await _settle();

      final playback = readState() as PlaybackPlaying;
      expect(playback.media.id, 2);
      expect(video.openedUrls.last, endsWith('/2/stream'));
    });

    test('error converts to PlaybackError state', () async {
      audio.loadError = Exception('boom');

      // Ошибка не пробрасывается в UI-вызовы (она уже отражена в
      // PlaybackState.error), но и не теряется молча.
      await expectLater(
        queue.setQueue([_media(1, MediaType.audio)]),
        completes,
      );
      expect(readState(), isA<PlaybackError>());
    });

    test('offline cache lookup failure falls back to streaming', () async {
      final errorContainer = containerWithCache(
        (ref) => _ThrowingCache(ref, 'http://test/api', Exception('boom')),
      );
      addTearDown(errorContainer.dispose);

      await errorContainer.read(playQueueProvider.notifier).setQueue([
        _media(1, MediaType.audio),
      ]);
      await _settle();

      final playback = errorContainer.read(playbackCoordinatorProvider);
      expect(playback, isA<PlaybackPlaying>());
      expect(audio.playlist.single.url, 'http://test/api/media/1/stream');
    });
  });

  group('PlaybackCoordinator mutual exclusion', () {
    test('starting audio stops video', () async {
      await queue.setQueue([_media(1, MediaType.video)]);
      // Старт видео сам останавливает аудио (взаимное исключение).
      expect(video.stopCalls, 0);
      expect(audio.stopCalls, 1);

      await queue.setQueue([_media(2, MediaType.audio)]);

      expect(video.stopCalls, 1);
      expect(audio.stopCalls, 1);
      expect(readState(), isA<PlaybackPlaying>());
      expect((readState() as PlaybackPlaying).type, MediaType.audio);
    });

    test('starting video stops audio', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);
      // Старт аудио сам останавливает видео.
      expect(video.stopCalls, 1);

      await queue.setQueue([_media(2, MediaType.video)]);

      expect(audio.stopCalls, 1);
      expect(video.stopCalls, 1);
      expect((readState() as PlaybackPlaying).type, MediaType.video);
    });
  });

  group('PlaybackCoordinator auto-advance', () {
    test(
      'mpv advances the playlist on its own, dart does not move it',
      () async {
        // mpv поднят с --keep-open=yes, а это «Don't terminate if the
        // current file is the last playlist entry»: при наличии следующего
        // элемента mpv листает плейлист САМ. Если Dart на EOF ещё и сам
        // дёргает next(), индекс сдвигается второй раз и трек пропускается.
        await queue.setQueue([
          _media(1, MediaType.audio),
          _media(2, MediaType.audio),
          _media(3, MediaType.audio),
        ]);
        expect((readState() as PlaybackPlaying).media.id, 1);

        audio.emitCompleted();
        await _settle();

        // Ровно один переход — тот, что сделал mpv.
        expect(audio.nextCalls, 0);
        expect(audio.loadSourceCalls, 1);
        expect(queue.state.currentIndex, 1);
        // Состояние пришло из playlistIndexStream, а не из вызова next().
        expect((readState() as PlaybackPlaying).media.id, 2);
      },
    );

    test('moves to completed state when queue ends', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);

      audio.emitCompleted();
      await _settle();

      expect(readState(), isA<PlaybackCompleted>());
      expect(audio.nextCalls, 0);
    });

    test('completed subscription survives the whole queue lifetime', () async {
      // Регрессия: раньше подписки пересоздавались на каждом переходе, и
      // EOF, пришедший в это окно, терялся безвозвратно — музыка просто
      // останавливалась. Теперь переходы не трогают подписки вовсе.
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
        _media(3, MediaType.audio),
      ]);

      for (var i = 0; i < 3; i++) {
        audio.emitCompleted();
        await _settle();
      }

      // Ни одного перехода из Dart: mpv дошёл до последнего трека сам.
      expect(readState(), isA<PlaybackCompleted>());
      expect(audio.nextCalls, 0);
      expect(queue.state.currentIndex, 2);
    });

    test(
      'EOF before mpv advanced does not report the queue as finished',
      () async {
        // Гонка порядка событий: eof-reached может прийти в Dart раньше,
        // чем mpv пришлёт START_FILE с новым индексом. Решение о конце
        // очереди принимается по индексу mpv с fallback на индекс очереди —
        // оба ещё 0, и очередь не считается исчерпанной.
        await queue.setQueue([
          _media(1, MediaType.audio),
          _media(2, MediaType.audio),
        ]);
        audio
          ..autoAdvanceOnEof = false
          ..emitCompleted();
        await _settle();

        expect(readState(), isA<PlaybackPlaying>());
        expect(queue.state.currentIndex, 0);
      },
    );

    test('failed track switch is an error, not the end of the queue', () async {
      // Отказ команды — это ошибка, а не «очередь кончилась»: раньше
      // `if (!advanced) state = completed` превращал сбой перехода в
      // PlaybackCompleted, и UI показывал остановку при живой музыке.
      await queue.setQueue([
        _media(1, MediaType.video),
        _media(2, MediaType.video),
      ]);
      video
        ..durationCtl.add(const Duration(seconds: 100))
        ..positionCtl.add(const Duration(seconds: 100))
        ..openError = Exception('boom');
      await _settle();

      video.completedCtl.add(true);
      await _settle();

      expect(readState(), isA<PlaybackError>());
    });

    test(
      'completion progress is saved for video before the next track starts',
      () async {
        await queue.setQueue([
          _media(1, MediaType.video),
          _media(2, MediaType.video),
        ]);
        video.durationCtl.add(const Duration(seconds: 100));
        video.positionCtl.add(const Duration(seconds: 100));
        await _settle();

        video.completedCtl.add(true);
        await _settle();

        expect((readState() as PlaybackPlaying).media.id, 2);
        final callsFor1 = repo.updates.where((u) => u.mediaId == 1).toList();
        expect(callsFor1, isNotEmpty);
        // Последний save для завершённого трека — именно completed:true,
        // и после него не было save с completed:false.
        expect(callsFor1.last.completed, isTrue);
      },
    );

    test('audio completion does not save progress', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      audio.durationCtl.add(const Duration(seconds: 100));
      audio.positionCtl.add(const Duration(seconds: 100));
      await _settle();
      expect(repo.updates, isEmpty);

      audio.emitCompleted();
      await _settle();

      expect((readState() as PlaybackPlaying).media.id, 2);
      // Для аудио прогресс не сохраняется вовсе.
      expect(repo.updates, isEmpty);
    });

    test('does not auto-advance while the queue is loading', () async {
      audio.loadGate = Completer<void>();
      final f = queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      await _settle();
      expect(readState(), isA<PlaybackLoading>());

      // EOF во время загрузки — не наш: пользователь переключает трек.
      audio.emitCompleted();
      audio.loadGate!.complete();
      await f;
      await _settle();

      expect((readState() as PlaybackPlaying).media.id, 1);
      expect(queue.state.currentIndex, 0);
      expect(audio.nextCalls, 0);
    });
  });

  group('PlaybackCoordinator playlist navigation', () {
    test('next/previous/jump use mpv commands, not playlist reloads', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
        _media(3, MediaType.audio),
      ]);

      expect(await queue.next(), isTrue);
      await _settle();
      expect(queue.state.currentIndex, 1);
      expect((readState() as PlaybackPlaying).media.id, 2);

      expect(await queue.previous(), isTrue);
      await _settle();
      expect(queue.state.currentIndex, 0);
      expect((readState() as PlaybackPlaying).media.id, 1);

      expect(await queue.jumpTo(2), isTrue);
      await _settle();
      expect(queue.state.currentIndex, 2);
      expect((readState() as PlaybackPlaying).media.id, 3);

      expect(audio.nextCalls, 1);
      expect(audio.previousCalls, 1);
      expect(audio.jumpTargets, [2]);
      expect(audio.loadSourceCalls, 1);
    });

    test('jumpTo an invalid index is a no-op', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);

      expect(await queue.jumpTo(5), isFalse);
      expect(audio.jumpCalls, 0);
    });

    test('enqueue appends to the mpv playlist without interrupting', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);
      final playsAfterStart = audio.playCalls;

      queue.enqueue(_media(2, MediaType.audio));
      await _settle();

      expect(audio.playlist, hasLength(2));
      expect(queue.state.currentIndex, 0);
      expect(audio.playCalls, playsAfterStart);
      expect(audio.loadSourceCalls, 1);
    });

    test('removeAt removes from the mpv playlist', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);

      queue.removeAt(1);
      await _settle();

      expect(audio.removeCalls, 1);
      expect(audio.removedIndexes, [1]);
      expect(audio.playlist, hasLength(1));
    });

    test('restartCurrent seeks to the beginning without reloading', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      await queue.jumpTo(1);
      await _settle();

      expect(await queue.playCurrent(), isTrue);
      await _settle();

      expect(audio.jumpTargets.last, 1);
      expect(audio.seeks.last, Duration.zero);
      expect(audio.loadSourceCalls, 1);
    });

    test(
      'reentrant next() is rejected instead of deadlocking the play chain',
      () async {
        // Регрессия: FluxAudioHandler.next() дёргал onNext, который вёл
        // в queue.next() → coordinator.next() → _serialize, ждущий сам
        // себя. Итог — вечная блокировка без исключения. Теперь вход
        // изнутри команды отклоняется, а цепочка остаётся рабочей.
        await queue.setQueue([
          _media(1, MediaType.audio),
          _media(2, MediaType.audio),
        ]);
        audio.onInsideCommand = () => queue.next();

        // Внешний вызов завершается (дедлока нет), а mpv-команда
        // отправляется ровно один раз: реентрантный отклонён до фейка.
        expect(await queue.next(), isTrue);
        await _settle();
        expect(audio.nextCalls, 1);
        expect(queue.state.currentIndex, 1);

        // Цепочка _playChain осталась рабочей.
        await queue.setQueue([_media(7, MediaType.audio)]);
        await _settle();
        expect((readState() as PlaybackPlaying).media.id, 7);
      },
    );

    test('reentrant jump() is rejected and leaves the queue usable', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      audio.onInsideCommand = () async {
        await coordinator.jump(0);
      };

      expect(await queue.jumpTo(1), isTrue);
      await _settle();
      // Реентрантный jump(0) не дошёл до mpv — иначе трек прыгнул бы
      // дважды.
      expect(audio.jumpTargets, [1]);
      expect(queue.state.currentIndex, 1);
    });

    test(
      'removing a track before the current shifts the mpv index down',
      () async {
        // Дискриминирующий случай для правила индекса: media_kit уменьшает
        // индекс, только когда текущий БОЛЬШЕ удаляемого (real.dart:551-554).
        // Прежний фейк делал ровно наоборот, а оба правила сходятся, когда
        // удаляют элемент с индексом, равным текущему, — поэтому старые тесты
        // проходили и с неверным фейком.
        // Четыре элемента, а не три: при трёх неверный индекс 2 обрезался бы
        // clamp'ом до 1 и совпал бы с верным — случай перестал бы
        // дискриминирующим.
        await queue.setQueue([
          _media(1, MediaType.audio),
          _media(2, MediaType.audio),
          _media(3, MediaType.audio),
          _media(4, MediaType.audio),
        ], startIndex: 2);
        await _settle();
        expect(audio.playlistIndex, 2);
        expect(queue.state.currentIndex, 2);

        queue.removeAt(0);
        await _settle();

        expect(audio.removedIndexes, [0]);
        // mpv: current 2 > removed 0 → индекс 1 (не 2).
        expect(audio.playlistIndex, 1);
        expect(queue.state.currentIndex, 1);
        expect(queue.state.items.map((m) => m.id), [2, 3, 4]);
        expect((readState() as PlaybackPlaying).media.id, 3);
      },
    );

    test('удаление играющего последнего трека не воскрешает Playing', () async {
      // Порядок событий mpv в спец-ветке real.dart:504-528:
      // playing:false -> completed:true -> плейлист с новым индексом.
      // _onMpvPlaylistIndex не должен превращать PlaybackCompleted в
      // Playing(isPaused: false) — плеер-то стоит.
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
        _media(3, MediaType.audio),
      ], startIndex: 2);
      await _settle();
      expect(readState(), isA<PlaybackPlaying>());
      audio.autoAdvanceOnEof = false;

      queue.removeAt(2);
      await _settle();

      // Индекс очереди следует за mpv даже при раннем возврате.
      expect(audio.playlistIndex, 1);
      expect(queue.state.currentIndex, 1);
      // А состояние остаётся завершённым, а не «играет на паузе».
      expect(readState(), isA<PlaybackCompleted>());
    });

    test('mpv: индекс после open() приходит уже playing, не паузой', () async {
      // real.dart:218-232: выход из паузы (playing:true) происходит ДО
      // установки playlist-pos, поэтому индекс приходит уже «playing».
      // Если open() молчит про playing, _lastPlayingSignal остаётся false
      // и индексный эмит записал бы isPaused: true — состояние, которого
      // mpv не создаёт.
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
        _media(3, MediaType.audio),
      ]);
      await _settle();

      expect((readState() as PlaybackPlaying).media.id, 1);
      expect((readState() as PlaybackPlaying).isPaused, isFalse);

      // Тот же порядок при автопереходе: mpv шлёт индекс, а не координатор.
      await audio.jump(1);
      await _settle();

      expect((readState() as PlaybackPlaying).media.id, 2);
      // Ключевая проверка: индексный эмит не должен помечать playing паузой.
      expect((readState() as PlaybackPlaying).isPaused, isFalse);
    });

    test(
      'consecutive commands are queued, not rejected as reentrant',
      () async {
        // Флаг поднимается только на время выполнения команды, поэтому
        // вторая команда (второй тап по «вперёд»), пришедшая до её запуска,
        // встаёт в _playChain и выполняется штатно, а не отбрасывается.
        await queue.setQueue([
          _media(1, MediaType.audio),
          _media(2, MediaType.audio),
          _media(3, MediaType.audio),
        ]);

        final first = queue.next();
        final second = queue.next();
        expect(await first, isTrue);
        expect(await second, isTrue);
        await _settle();

        expect(audio.nextCalls, 2);
        expect(queue.state.currentIndex, 2);
        expect(readState(), isA<PlaybackPlaying>());
      },
    );

    test('removeAt keeps queue index aligned with the mpv playlist', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
        _media(3, MediaType.audio),
      ]);
      // Удаляем текущий: mpv продолжает со следующего, индекс прежний.
      queue.removeAt(0);
      await _settle();
      expect(audio.removedIndexes, [0]);
      expect(queue.state.currentIndex, 0);
      expect(queue.state.items.first.id, 2);
      expect((readState() as PlaybackPlaying).media.id, 2);

      // Удаляем трек перед текущим: mpv уменьшает индекс.
      queue.removeAt(0);
      await _settle();
      expect(audio.removedIndexes, [0, 0]);
      expect(queue.state.currentIndex, 0);
      expect(queue.state.items.single.id, 3);
    });

    test(
      'reload on auth token change keeps position and picks new headers',
      () async {
        await container.read(settingsProvider.notifier).setTokens('t1', 'r1');
        await queue.setQueue([
          _media(1, MediaType.audio),
          _media(2, MediaType.audio),
        ]);
        await _settle();
        audio.positionCtl.add(const Duration(seconds: 30));
        await _settle();
        expect(audio.playlist.first.httpHeaders, {
          'Authorization': 'Bearer t1',
        });
        final loadsBefore = audio.loadSourceCalls;

        await container.read(settingsProvider.notifier).setTokens('t2', 'r2');
        await _settle();

        expect(audio.loadSourceCalls, loadsBefore + 1);
        expect(audio.playlist.first.httpHeaders, {
          'Authorization': 'Bearer t2',
        });
        expect(audio.seeks.last, const Duration(seconds: 30));
      },
    );
  });

  group('PlaybackCoordinator video progress', () {
    test(
      'saves progress of the playing video before switching tracks',
      () async {
        // Регрессия: блок сохранения прогресса из старого _playInternal
        // не переехал в _startQueue, и уход с видео на другой трек терял
        // до 10 секунд прогресса (таймер автосохранения мог не успеть).
        await queue.setQueue([_media(1, MediaType.video)]);
        video.durationCtl.add(const Duration(seconds: 100));
        video.positionCtl.add(const Duration(seconds: 42));
        await _settle();
        repo.updates.clear();

        await queue.setQueue([_media(2, MediaType.video)]);
        await _settle();

        final for1 = repo.updates.where((u) => u.mediaId == 1).toList();
        expect(for1, isNotEmpty);
        expect(for1.first.position, 42);
      },
    );

    test(
      'stop() while the progress save is in flight does not strand loading',
      () async {
        // Регрессия: между await _saveProgress(...) и state = loading()
        // было сетевое окно без проверки поколения. stop() ставил
        // PlaybackInitial, следующая строка затирала его на loading, и
        // последующая generation-проверка уходила в return — состояние
        // залипало в loading при остановленном плеере.
        repo.progressGate = Completer<void>();
        await queue.setQueue([_media(1, MediaType.video)]);
        video
          ..durationCtl.add(const Duration(seconds: 100))
          ..positionCtl.add(const Duration(seconds: 40))
          ..openGate = Completer<void>();
        await _settle();
        expect(readState(), isA<PlaybackPlaying>());

        final switching = queue.setQueue([_media(2, MediaType.video)]);
        await _settle();

        // Не await: stop() инкрементит поколение синхронно, до своего
        // первого await, а сам ждёт той же _saveChain.
        final stopping = coordinator.stop();
        video.openGate!.complete();
        repo.progressGate!.complete();
        await Future.wait([switching, stopping]);
        await _settle();

        expect(readState(), isA<PlaybackInitial>());
        expect(video.playCalls, 1);
      },
    );

    test('does not double-save when the video ends and advances', () async {
      await queue.setQueue([
        _media(1, MediaType.video),
        _media(2, MediaType.video),
      ]);
      video.durationCtl.add(const Duration(seconds: 100));
      video.positionCtl.add(const Duration(seconds: 100));
      await _settle();
      repo.updates.clear();

      video.completedCtl.add(true);
      await _settle();

      final for1 = repo.updates.where((u) => u.mediaId == 1).toList();
      // Ровно одно сохранение — completed:true из _onCompleted.
      // Второго completed:false быть не должно: следующий трек стартует
      // из состояния loading.
      expect(for1, hasLength(1));
      expect(for1.single.completed, isTrue);
    });
  });

  group('PlaybackCoordinator resume logic', () {
    test('resumes immediately when saved position <= 5s', () async {
      repo.progress = [const WatchProgress(userId: 1, mediaId: 9, position: 4)];

      await queue.setQueue([_media(9, MediaType.video)]);

      final playback = readState() as PlaybackPlaying;
      expect(playback.savedPosition, isNull);
      expect(video.seekCalls, [const Duration(seconds: 4)]);
    });

    test('shows resume overlay when saved position > 5s', () async {
      repo.progress = [
        const WatchProgress(userId: 1, mediaId: 9, position: 30),
      ];

      await queue.setQueue([_media(9, MediaType.video)]);

      final playback = readState() as PlaybackPlaying;
      expect(playback.savedPosition, const Duration(seconds: 30));
      expect(video.seekCalls, isEmpty);
    });

    test('seekToSavedPosition seeks and clears the overlay', () async {
      repo.progress = [
        const WatchProgress(userId: 1, mediaId: 9, position: 30),
      ];
      await queue.setQueue([_media(9, MediaType.video)]);
      video.seekCalls.clear();

      await coordinator.seekToSavedPosition();

      expect(video.seekCalls, [const Duration(seconds: 30)]);
      expect((readState() as PlaybackPlaying).savedPosition, isNull);
    });
  });

  group('PlaybackCoordinator.stop', () {
    test('stops audio playback and resets state', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);

      await coordinator.stop();

      expect(audio.stopCalls, 1);
      expect(readState(), isA<PlaybackInitial>());
    });

    test('stops audio player even in completed state', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);
      audio.emitCompleted();
      await _settle();
      expect(readState(), isA<PlaybackCompleted>());
      audio.stopCalls = 0;

      await coordinator.stop();

      // Уведомление audio_service должно быть убрано — плеер остановлен.
      expect(audio.stopCalls, 1);
      expect(readState(), isA<PlaybackInitial>());
    });

    test('stops video player during loading and aborts pending play', () async {
      video.openGate = Completer<void>();
      final f = queue.setQueue([_media(1, MediaType.video)]);
      await _settle();
      expect(readState(), isA<PlaybackLoading>());

      await coordinator.stop();
      expect(video.stopCalls, 1);

      video.openGate!.complete();
      await f;
      await _settle();

      // Незавершённый play не перезапускает воспроизведение после stop.
      expect(video.playCalls, 0);
      expect(readState(), isA<PlaybackInitial>());
    });
  });

  group('PlaybackCoordinator.pause/resume', () {
    test('pause saves progress and resume continues', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);
      audio.positionCtl.add(const Duration(seconds: 42));
      await _settle();

      await coordinator.pause();
      expect(audio.pauseCalls, 1);
      expect((readState() as PlaybackPlaying).isPaused, isTrue);

      await coordinator.resume();
      expect(audio.playCalls, 2);
      expect((readState() as PlaybackPlaying).isPaused, isFalse);
    });
  });
}

class _ThrowingCache extends OfflineCacheService {
  new(super.ref, super.baseUrl, this._error);

  final Exception _error;

  @override
  Future<String?> getLocalPath(int mediaId) async => throw _error;
}

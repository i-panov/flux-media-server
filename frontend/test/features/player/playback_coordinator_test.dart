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

Media _media(int id, MediaType type) => Media(
      id: id,
      title: 'Media $id',
      year: 2024,
      type: type,
      fileSize: 1024,
    );

/// Settles all pending microtasks and short futures.
Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeAudioSource implements AudioPlaybackSource {
  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();
  final errorCtl = StreamController<String>.broadcast();
  final bufferingCtl = StreamController<bool>.broadcast();
  final volumeCtl = StreamController<double>.broadcast();

  int loadSourceCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int seekCalls = 0;
  int setVolumeCalls = 0;
  @override
  double volume = 100;
  final List<String> openedUrls = [];

  /// Когда задан, loadSource() ждёт его — для эмуляции долгой загрузки.
  Completer<void>? loadGate;

  @override
  Future<void> loadSource({
    required String url,
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
    Map<String, String>? httpHeaders,
  }) async {
    if (loadGate != null) await loadGate!.future;
    loadSourceCalls++;
    openedUrls.add(url);
  }

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> seek(Duration position) async => seekCalls++;

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

  void emitCompleted() => completedCtl.add(true);

  void disposeStreams() {
    for (final c in [
      positionCtl,
      durationCtl,
      playingCtl,
      completedCtl,
      errorCtl,
      bufferingCtl,
      volumeCtl,
    ]) {
      c.close();
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

  @override
  Player get player => throw UnimplementedError();

  @override
  Future<void> open(String url, {Map<String, String>? httpHeaders}) async {
    if (openGate != null) await openGate!.future;
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
      c.close();
    }
  }
}

class _FakeMediaRepository implements MediaRepository {
  List<WatchProgress> progress = [];

  /// (mediaId, position, duration, completed) в порядке вызовов.
  final List<({int mediaId, int position, int duration, bool? completed})>
      updates = [];

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
    updates.add(
      (
        mediaId: mediaId,
        position: position ?? 0,
        duration: duration ?? 0,
        completed: completed,
      ),
    );
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
  }) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  ) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) =>
      throw UnimplementedError();

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
  _FakeOfflineCache(super.ref, super.baseUrl);

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

  setUp(() {
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
    addTearDown(() {
      container.dispose();
      audio.disposeStreams();
      video.disposeStreams();
    });
  });

  PlaybackState readState() => container.read(playbackCoordinatorProvider);

  group('PlaybackCoordinator.play', () {
    test('starts audio playback and sets playing state', () async {
      await coordinator.play(_media(1, MediaType.audio));

      expect(readState(), isA<PlaybackPlaying>());
      expect((readState() as PlaybackPlaying).type, MediaType.audio);
      expect(audio.loadSourceCalls, 1);
      expect(audio.playCalls, 1);
    });

    test('starts video playback and sets playing state', () async {
      await coordinator.play(_media(1, MediaType.video));

      expect(readState(), isA<PlaybackPlaying>());
      expect((readState() as PlaybackPlaying).type, MediaType.video);
      expect(video.openCalls, 1);
      expect(video.playCalls, 1);
    });

    test('concurrent play calls serialize, the last media wins', () async {
      final f1 = coordinator.play(_media(1, MediaType.video));
      final f2 = coordinator.play(_media(2, MediaType.video));
      await Future.wait([f1, f2]);
      await _settle();

      final playback = readState() as PlaybackPlaying;
      expect(playback.media.id, 2);
      expect(video.openCalls, 2);
      expect(video.openedUrls.last, endsWith('/2/stream'));
    });

    test('error converts to PlaybackError state', () async {
      final errorContainer = ProviderContainer(
        overrides: [
          audioPlayerDatasourceProvider.overrideWithValue(audio),
          baseUrlProvider.overrideWithValue('http://test/api'),
          playbackCoordinatorProvider.overrideWith(PlaybackCoordinator.new),
          videoPlayerDatasourceProvider.overrideWithValue(video),
          mediaRepositoryProvider.overrideWithValue(repo),
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(),
          ),
          offlineCacheServiceProvider.overrideWith(
            (ref) => _ThrowingCache(ref, 'http://test/api', Exception('boom')),
          ),
        ],
      );
      addTearDown(errorContainer.dispose);
      final failingCoordinator =
          errorContainer.read(playbackCoordinatorProvider.notifier);

      await expectLater(
        failingCoordinator.play(_media(1, MediaType.audio)),
        throwsA(isA<Exception>()),
      );
      expect(
        errorContainer.read(playbackCoordinatorProvider),
        isA<PlaybackError>(),
      );
    });
  });

  group('PlaybackCoordinator mutual exclusion', () {
    test('starting audio stops video', () async {
      await coordinator.play(_media(1, MediaType.video));
      // Старт видео сам останавливает аудио (взаимное исключение).
      expect(video.stopCalls, 0);
      expect(audio.stopCalls, 1);

      await coordinator.play(_media(2, MediaType.audio));

      expect(video.stopCalls, 1);
      expect(audio.stopCalls, 1);
      expect(readState(), isA<PlaybackPlaying>());
      expect((readState() as PlaybackPlaying).type, MediaType.audio);
    });

    test('starting video stops audio', () async {
      await coordinator.play(_media(1, MediaType.audio));
      // Старт аудио сам останавливает видео.
      expect(video.stopCalls, 1);

      await coordinator.play(_media(2, MediaType.video));

      expect(audio.stopCalls, 1);
      expect(video.stopCalls, 1);
      expect((readState() as PlaybackPlaying).type, MediaType.video);
    });
  });

  group('PlaybackCoordinator auto-advance', () {
    test('advances to next queue item on completion', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      expect((readState() as PlaybackPlaying).media.id, 1);

      audio.emitCompleted();
      await _settle();

      final playback = readState() as PlaybackPlaying;
      expect(playback.media.id, 2);
      expect(queue.state.currentIndex, 1);
    });

    test('moves to completed state when queue ends', () async {
      await queue.setQueue([_media(1, MediaType.audio)]);

      audio.emitCompleted();
      await _settle();

      expect(readState(), isA<PlaybackCompleted>());
    });

    test('completion progress is saved before the next track starts', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      audio.durationCtl.add(const Duration(seconds: 100));
      audio.positionCtl.add(const Duration(seconds: 100));
      await _settle();

      audio.emitCompleted();
      await _settle();

      expect((readState() as PlaybackPlaying).media.id, 2);
      final callsFor1 = repo.updates.where((u) => u.mediaId == 1).toList();
      expect(callsFor1, isNotEmpty);
      // Последний save для завершённого трека — именно completed:true,
      // и после него не было save с completed:false.
      expect(callsFor1.last.completed, isTrue);
    });

    test('does not auto-advance while loading another track', () async {
      await queue.setQueue([
        _media(1, MediaType.audio),
        _media(2, MediaType.audio),
      ]);
      expect((readState() as PlaybackPlaying).media.id, 1);

      // Пользователь переключает трек — состояние loading.
      audio.loadGate = Completer<void>();
      final f = coordinator.play(_media(2, MediaType.audio));
      await _settle();
      expect(readState(), isA<PlaybackLoading>());

      // completed старого трека не должен запускать авто-продвижение.
      audio.emitCompleted();
      audio.loadGate!.complete();
      await f;
      await _settle();

      expect((readState() as PlaybackPlaying).media.id, 2);
      expect(queue.state.currentIndex, 0);
    });
  });

  group('PlaybackCoordinator resume logic', () {
    test('resumes immediately when saved position <= 5s', () async {
      repo.progress = [
        const WatchProgress(userId: 1, mediaId: 9, position: 4),
      ];

      await coordinator.play(_media(9, MediaType.video));

      final playback = readState() as PlaybackPlaying;
      expect(playback.savedPosition, isNull);
      expect(video.seekCalls, [const Duration(seconds: 4)]);
    });

    test('shows resume overlay when saved position > 5s', () async {
      repo.progress = [
        const WatchProgress(userId: 1, mediaId: 9, position: 30),
      ];

      await coordinator.play(_media(9, MediaType.video));

      final playback = readState() as PlaybackPlaying;
      expect(playback.savedPosition, const Duration(seconds: 30));
      expect(video.seekCalls, isEmpty);
    });

    test('seekToSavedPosition seeks and clears the overlay', () async {
      repo.progress = [
        const WatchProgress(userId: 1, mediaId: 9, position: 30),
      ];
      await coordinator.play(_media(9, MediaType.video));
      video.seekCalls.clear();

      await coordinator.seekToSavedPosition();

      expect(video.seekCalls, [const Duration(seconds: 30)]);
      expect((readState() as PlaybackPlaying).savedPosition, isNull);
    });
  });

  group('PlaybackCoordinator.stop', () {
    test('stops audio playback and resets state', () async {
      await coordinator.play(_media(1, MediaType.audio));

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
      final f = coordinator.play(_media(1, MediaType.video));
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
      await coordinator.play(_media(1, MediaType.audio));
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
  _ThrowingCache(super.ref, super.baseUrl, this._error);

  final Exception _error;

  @override
  Future<String?> getLocalPath(int mediaId) async => throw _error;
}

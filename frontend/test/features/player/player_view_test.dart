import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_view.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';
import 'package:media_kit/media_kit.dart' hide Media;

Media _media(int id, MediaType type) =>
    Media(id: id, title: 'Media $id', year: 2024, type: type, fileSize: 1024);

class _FakeAudioSource implements AudioPlaybackSource {
  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();
  final errorCtl = StreamController<String>.broadcast();
  final bufferingCtl = StreamController<bool>.broadcast();
  final volumeCtl = StreamController<double>.broadcast();

  @override
  double volume = 100;

  @override
  Future<void> loadSource({
    required String url,
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
    Map<String, String>? httpHeaders,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

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

  @override
  double rate = 1;

  @override
  Duration position = Duration.zero;

  @override
  Player get player => throw UnimplementedError();

  @override
  Future<void> open(String url, {Map<String, String>? httpHeaders}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRate(double rate) async {}

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
  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
      const Right([]);

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async => Right(
    WatchProgress(
      userId: 1,
      mediaId: mediaId,
      position: position ?? 0,
      duration: duration ?? 0,
      completed: completed ?? false,
    ),
  );

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

/// Считает пересоздания консьюмера, который слушает ровно тот же селектор,
/// что и панель управления видеоплеера.
class _BuildProbe extends ConsumerWidget {
  const new({required this.onBuild});
  final void Function(PlayerView view) onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      playbackCoordinatorProvider.select(playerViewFromPlaybackState),
    );
    onBuild(view);
    return Text(view.kind.name);
  }
}

void main() {
  late _FakeAudioSource audio;
  late _FakeVideoSource video;
  late ProviderContainer container;

  setUp(() {
    audio = _FakeAudioSource();
    video = _FakeVideoSource();
    container = ProviderContainer(
      overrides: [
        audioPlayerDatasourceProvider.overrideWithValue(audio),
        baseUrlProvider.overrideWithValue('http://test/api'),
        playbackCoordinatorProvider.overrideWith(PlaybackCoordinator.new),
        videoPlayerDatasourceProvider.overrideWithValue(video),
        mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        offlineCacheServiceProvider.overrideWith(
          (ref) => _FakeOfflineCache(ref, 'http://test/api'),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      audio.disposeStreams();
      video.disposeStreams();
    });
  });

  testWidgets('панель управления не пересоздаётся на тики позиции', (
    tester,
  ) async {
    var builds = 0;
    PlayerView? last;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: _BuildProbe(
            onBuild: (view) {
              builds++;
              last = view;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(builds, 1, reason: 'начальное состояние — один build');

    final coordinator = container.read(playbackCoordinatorProvider.notifier);
    await coordinator.play(_media(1, MediaType.video));
    await tester.pump();
    expect(last!.kind, PlayerViewKind.playing);
    final buildsAfterPlay = builds;
    expect(buildsAfterPlay, greaterThan(1));

    // Тики позиции меняют только position в PlaybackState; панель должна
    // оставаться прежней (media_kit рисует прогресс сам).
    for (final pos in [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 3),
      const Duration(seconds: 4),
    ]) {
      video.positionCtl.add(pos);
      await tester.pump();
    }
    expect(
      builds,
      buildsAfterPlay,
      reason: 'тики позиции не должны пересоздавать панель управления',
    );

    // Реальное изменение состояния (пауза) обязано пересоздать панель.
    await coordinator.pause();
    await tester.pump();
    expect(last!.isPaused, isTrue);
    expect(builds, greaterThan(buildsAfterPlay));

    // Останавливаем плеер: гасим периодический progress-таймер,
    // иначе тест упадёт на pending-timer invariant.
    await coordinator.stop();
    await tester.pump();
  });
}

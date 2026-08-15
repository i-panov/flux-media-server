import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/watch_progress_provider.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';

WatchProgress _progress(int id) => WatchProgress(
      id: id,
      userId: 7,
      mediaId: id,
      position: id * 100,
      duration: id * 200,
      completed: id.isOdd,
      updatedAt: DateTime.utc(2024),
    );

class FakeMediaRepository implements MediaRepository {
  Future<Either<Failure, List<WatchProgress>>> Function()? onGetProgress;

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() =>
      onGetProgress!();

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async =>
      const Right((items: [], total: 0));

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, void>> deleteMedia(int id) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, List<Artist>>> getArtists() async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
      checkHash(String hash) async =>
          const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, UploadStatus>> getUploadStatus(int jobId) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, void>> cancelUpload(int jobId) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, List<Media>>> getMediaBulk(List<int> ids) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  ) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, void>> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) async =>
      const Left(ServerFailure(message: 'not used'));
}

/// Фейк датасорса: записывает параметры updateProgress.
class _FakeMediaRemoteDataSource extends MediaRemoteDataSource {
  _FakeMediaRemoteDataSource()
      : super(
          MediaApiClient.create(baseUrl: 'http://localhost:8080/api').apiClient,
        );

  int? lastMediaId;
  int? lastPosition;
  int? lastDuration;
  bool? lastCompleted;

  @override
  Future<WatchProgress> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async {
    lastMediaId = mediaId;
    lastPosition = position;
    lastDuration = duration;
    lastCompleted = completed;
    return WatchProgress(
      id: 1,
      userId: 7,
      mediaId: mediaId,
      position: position ?? 0,
      duration: duration ?? 0,
      completed: completed ?? false,
      updatedAt: DateTime.utc(2024),
    );
  }
}

void main() {
  group('watchProgressProvider', () {
    late ProviderContainer container;
    late FakeMediaRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeMediaRepository();
      container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('loads watch progress', () async {
      fakeRepo.onGetProgress = () async => Right([_progress(1), _progress(2)]);

      final result = await container.read(watchProgressProvider.future);

      expect(result, hasLength(2));
      expect(result.first.duration, 200);
      expect(result.first.completed, isTrue);
    });

    test('throws on repository failure', () async {
      fakeRepo.onGetProgress =
          () async => const Left(ServerFailure(message: 'Boom'));

      await expectLater(
        container.read(watchProgressProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MediaRepositoryImpl.updateProgress', () {
    late _FakeMediaRemoteDataSource datasource;
    late MediaRepositoryImpl repository;

    setUp(() {
      datasource = _FakeMediaRemoteDataSource();
      repository = MediaRepositoryImpl(datasource);
    });

    test('passes position, duration and completed to the data source',
        () async {
      final result = await repository.updateProgress(
        5,
        position: 100,
        duration: 5000,
        completed: true,
      );

      expect(datasource.lastMediaId, 5);
      expect(datasource.lastPosition, 100);
      expect(datasource.lastDuration, 5000);
      expect(datasource.lastCompleted, isTrue);
      expect(result.isRight(), isTrue);
      final progress = result.getOrElse(
        (_) => const WatchProgress(id: 0, userId: 0, mediaId: 0, position: 0),
      );
      expect(progress.position, 100);
      expect(progress.duration, 5000);
      expect(progress.completed, isTrue);
      expect(progress.updatedAt, isNotNull);
    });
  });
}

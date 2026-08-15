import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_media.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';

class FakeMediaRepository implements MediaRepository {
  Future<Either<Failure, Media>> Function({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  })? onUploadFile;

  String? lastFilePath;
  String? lastMediaType;
  String? lastFileName;
  bool Function()? lastIsCancelled;
  final List<(int, int?)> progressEvents = [];

  @override
  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) {
    lastFilePath = filePath;
    lastMediaType = mediaType;
    lastFileName = fileName;
    lastIsCancelled = isCancelled;
    return onUploadFile!(
      filePath: filePath,
      mediaType: mediaType,
      fileName: fileName,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

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
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
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

/// Датсорс-заглушка для проверки реальной цепочки отмены
/// (datasource → repository → Failure).
class _StubUploadDataSource extends MediaRemoteDataSource {
  _StubUploadDataSource(this._result)
      : super(
          MediaApiClient.create(baseUrl: 'http://localhost:8080/api')
              .apiClient,
        );

  final Object _result;

  @override
  Future<Media> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (_result is Exception) throw _result;
    if (_result is Error) throw _result;
    return _result as Media;
  }

  @override
  Future<void> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) async {
    if (_result is Exception) throw _result;
    if (_result is Error) throw _result;
  }
}

void main() {
  group('UploadMedia use case', () {
    late FakeMediaRepository fakeRepo;
    late UploadMedia uploadMedia;

    setUp(() {
      fakeRepo = FakeMediaRepository();
      uploadMedia = UploadMedia(fakeRepo);
    });

    test('passes file params and progress callback to the repository',
        () async {
      fakeRepo.onUploadFile =
          ({required filePath, required mediaType, required fileName,
              onProgress,
              isCancelled,
            }) async {
        onProgress?.call(10, 100);
        onProgress?.call(20, 100);
        return Right(
          Media(
            id: 1,
            title: fileName,
            year: 2024,
            type: MediaType.video,
            fileSize: 100,
          ),
        );
      };

      final result = await uploadMedia(
        UploadMediaParams(
          filePath: '/tmp/movie.mp4',
          mediaType: 'video',
          fileName: 'movie.mp4',
          onProgress: (sent, total) {
            fakeRepo.progressEvents.add((sent, total));
          },
        ),
      );

      expect(result.isRight(), isTrue);
      expect(fakeRepo.lastFilePath, '/tmp/movie.mp4');
      expect(fakeRepo.lastMediaType, 'video');
      expect(fakeRepo.lastFileName, 'movie.mp4');
      expect(fakeRepo.progressEvents, [(10, 100), (20, 100)]);
    });

    test('returns Left on repository failure', () async {
      fakeRepo.onUploadFile =
          ({required filePath, required mediaType, required fileName,
              onProgress,
              isCancelled,
            }) async =>
              const Left(ServerFailure(message: 'Too large'));

      final result = await uploadMedia(
        const UploadMediaParams(
          filePath: '/tmp/movie.mp4',
          mediaType: 'video',
          fileName: 'movie.mp4',
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(result.fold((l) => l.message, (_) => ''), 'Too large');
    });
  });

  group('MediaRepositoryImpl upload cancellation chain', () {
    test('cancellation becomes UploadCancelledFailure, not ServerFailure',
        () async {
      final repository = MediaRepositoryImpl(
        _StubUploadDataSource(const UploadCancelledException()),
      );

      final result = await repository.uploadFile(
        filePath: '/tmp/movie.mp4',
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => null);
      expect(failure, isA<UploadCancelledFailure>());
      expect(failure, isNot(isA<ServerFailure>()));
    });

    test('non-cancellation errors still map through safeRepositoryCall',
        () async {
      final repository = MediaRepositoryImpl(
        _StubUploadDataSource(const ServerException(message: 'Disk full')),
      );

      final result = await repository.uploadFile(
        filePath: '/tmp/movie.mp4',
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => null);
      expect(failure, isA<ServerFailure>());
      expect(failure?.message, 'Disk full');
    });

    test('successful upload returns the media', () async {
      const media = Media(
        id: 1,
        title: 'movie.mp4',
        year: 2024,
        type: MediaType.video,
        fileSize: 100,
      );
      final repository = MediaRepositoryImpl(_StubUploadDataSource(media));

      final result = await repository.uploadFile(
        filePath: '/tmp/movie.mp4',
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable()?.id, 1);
    });

    test('uploadCover also surfaces cancellation as UploadCancelledFailure',
        () async {
      final repository = MediaRepositoryImpl(
        _StubUploadDataSource(const UploadCancelledException()),
      );

      final result = await repository.uploadCover(5, '/tmp/cover.jpg');

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => null);
      expect(failure, isA<UploadCancelledFailure>());
    });
  });

  group('MediaRepositoryImpl.updateMetadata mapping', () {
    test('MetadataEdit is mapped to JSON in the data layer', () async {
      final datasource = _RecordingDataSource();
      final repository = MediaRepositoryImpl(datasource);

      await repository.updateMetadata(
        5,
        const MetadataEdit(
          title: 'New Title',
          artists: ['A', 'B'],
          year: 2020,
        ),
      );

      expect(datasource.lastMetadataId, 5);
      expect(
        datasource.lastMetadata,
        {
          'title': 'New Title',
          'artists': ['A', 'B'],
          'year': 2020,
        },
      );
    });
  });
}

class _RecordingDataSource extends MediaRemoteDataSource {
  _RecordingDataSource()
      : super(
          MediaApiClient.create(baseUrl: 'http://localhost:8080/api')
              .apiClient,
        );

  int? lastMetadataId;
  Map<String, dynamic>? lastMetadata;

  @override
  Future<Media> updateMetadata(int mediaId, Map<String, dynamic> data) async {
    lastMetadataId = mediaId;
    lastMetadata = data;
    return Media(
      id: mediaId,
      title: data['title'] as String,
      year: 2020,
      type: MediaType.video,
      fileSize: 100,
    );
  }
}

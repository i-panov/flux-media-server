import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
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
    Map<String, dynamic> data,
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
    String filePath,
  ) async =>
      const Left(ServerFailure(message: 'not used'));
}

void main() {
  late FakeMediaRepository fakeRepo;
  late UploadMedia uploadMedia;

  setUp(() {
    fakeRepo = FakeMediaRepository();
    uploadMedia = UploadMedia(fakeRepo);
  });

  test('passes file params and progress callback to the repository', () async {
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

  test('propagates UploadCancelledException instead of swallowing it',
      () async {
    fakeRepo.onUploadFile =
        ({required filePath, required mediaType, required fileName,
            onProgress,
            isCancelled,
          }) async {
      if (isCancelled?.call() ?? false) {
        throw const UploadCancelledException();
      }
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

    await expectLater(
      uploadMedia(
        UploadMediaParams(
          filePath: '/tmp/movie.mp4',
          mediaType: 'video',
          fileName: 'movie.mp4',
          isCancelled: () => true,
        ),
      ),
      throwsA(isA<UploadCancelledException>()),
    );
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
}

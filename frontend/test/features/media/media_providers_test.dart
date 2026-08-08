import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_detail.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

Media _fakeMedia(int id, [String? title]) => Media(
      id: id,
      title: title ?? 'Media $id',
      year: 2024,
      type: 'movie',
      filePath: '/path/$id.mp4',
      fileSize: 1024,
    );

class FakeMediaRepository implements MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> Function({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  })? onGetMediaList;
  Future<Either<Failure, Media>> Function(int)? onGetMediaDetail;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) =>
      onGetMediaList!(type: type, year: year, q: q, limit: limit, offset: offset);

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) =>
      onGetMediaDetail!(id);

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
      checkHash(String hash) async =>
          const Right((exists: false, mediaId: null, title: null));

  @override
  Future<Either<Failure, Media>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
  }) async =>
      Right(_fakeMedia(0, fileName));

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
      const Right([]);

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    Map<String, dynamic> data,
  ) async =>
      Right(_fakeMedia(mediaId));

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
  }) async =>
      const Right(WatchProgress(
        id: 0,
        userId: 0,
        mediaId: 0,
        position: 0,
      ));

  @override
  Future<Either<Failure, void>> uploadCover(int mediaId, String filePath) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> deleteMedia(int id) async =>
      const Right(null);
}

void main() {
  group('MediaListNotifier', () {
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

    test('loads media list', () async {
      final items = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList =
          ({type, year, q, limit, offset}) async => Right((items: items, total: 2));

      final result = await container.read(mediaListProvider('video').future);
      expect(result.items, hasLength(2));
      expect(result.total, 2);
    });

    test('loadMore appends items', () async {
      final first = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList =
          ({type, year, q, limit, offset}) async => Right((items: first, total: 4));

      await container.read(mediaListProvider('video').future);

      final second = [_fakeMedia(3), _fakeMedia(4)];
      fakeRepo.onGetMediaList =
          ({type, year, q, limit, offset}) async => Right((items: second, total: 4));

      await container.read(mediaListProvider('video').notifier).loadMore();

      final state = container.read(mediaListProvider('video')).value;
      expect(state?.items, hasLength(4));
    });
  });

  group('MediaDetailNotifier', () {
    late ProviderContainer container;
    late FakeMediaRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeMediaRepository();
      container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(fakeRepo),
          getMediaDetailUseCaseProvider.overrideWithValue(GetMediaDetail(fakeRepo)),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('load emits loaded with media', () async {
      final media = _fakeMedia(1, 'The Matrix');
      fakeRepo.onGetMediaDetail = (_) async => Right(media);

      final notifier = container.read(mediaDetailProvider(1).notifier);
      await notifier.load(1);

      final state = container.read(mediaDetailProvider(1));
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'The Matrix');
    });

    test('load emits error on failure', () async {
      fakeRepo.onGetMediaDetail =
          (_) async => const Left(ServerFailure(message: 'Not found'));

      final notifier = container.read(mediaDetailProvider(999).notifier);
      await notifier.load(999);

      final state = container.read(mediaDetailProvider(999));
      expect(state, isA<MediaDetailError>());
      expect((state as MediaDetailError).message, 'Not found');
    });
  });
}

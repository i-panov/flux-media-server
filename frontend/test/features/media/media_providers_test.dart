import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_detail.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia(int id, [String? title]) => Media(
      id: id,
      title: title ?? 'Media $id',
      year: 2024,
      type: 'movie',
      filePath: '/path/$id.mp4',
      fileSize: 1024,
    );

class FakeMediaRepository implements MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> Function(
      {String? type, int? year, String? q, int? limit, int? offset})? onGetMediaList;
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

      final result = await container.read(mediaListProvider.future);
      expect(result.items, hasLength(2));
      expect(result.total, 2);
    });

    test('loadMore appends items', () async {
      final first = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList =
          ({type, year, q, limit, offset}) async => Right((items: first, total: 4));

      await container.read(mediaListProvider.future);

      final second = [_fakeMedia(3), _fakeMedia(4)];
      fakeRepo.onGetMediaList =
          ({type, year, q, limit, offset}) async => Right((items: second, total: 4));

      await container.read(mediaListProvider.notifier).loadMore();

      final state = container.read(mediaListProvider).value;
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

      final notifier = container.read(mediaDetailProvider.notifier);
      await notifier.load(1);

      final state = container.read(mediaDetailProvider);
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'The Matrix');
    });

    test('load emits error on failure', () async {
      fakeRepo.onGetMediaDetail =
          (_) async => const Left(ServerFailure(message: 'Not found'));

      final notifier = container.read(mediaDetailProvider.notifier);
      await notifier.load(999);

      final state = container.read(mediaDetailProvider);
      expect(state, isA<MediaDetailError>());
      expect((state as MediaDetailError).message, 'Not found');
    });
  });
}

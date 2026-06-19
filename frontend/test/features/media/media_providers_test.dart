import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_list.dart';
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
      GetMediaListParams)? onGetMediaList;
  Future<Either<Failure, Media>> Function(int)? onGetMediaDetail;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    int? limit,
    int? offset,
  }) =>
      onGetMediaList!(GetMediaListParams(
        type: type,
        year: year,
        limit: limit,
        offset: offset,
      ));

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) =>
      onGetMediaDetail!(id);
}

void main() {
  group('MediaListNotifier', () {
    late MediaListNotifier notifier;
    late FakeMediaRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeMediaRepository();
      notifier = MediaListNotifier(
        getMediaList: GetMediaList(fakeRepo),
      );
    });

    tearDown(() => notifier.dispose());

    test('initial state is loading', () {
      expect(notifier.state, isA<MediaListLoading>());
    });

    test('load emits loaded with items', () async {
      final items = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList = (_) async => Right((items: items, total: 2));

      await notifier.load();

      final loaded = notifier.state as MediaListLoaded;
      expect(loaded.items, hasLength(2));
      expect(loaded.total, 2);
      expect(loaded.hasReachedMax, true);
    });

    test('load emits error on failure', () async {
      fakeRepo.onGetMediaList =
          (_) async => const Left(ServerFailure(message: 'Server error'));

      await notifier.load();

      expect(notifier.state, isA<MediaListError>());
      expect((notifier.state as MediaListError).message, 'Server error');
    });

    test('loadMore appends items', () async {
      final first = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList = (_) async => Right((items: first, total: 4));

      await notifier.load();

      final second = [_fakeMedia(3), _fakeMedia(4)];
      fakeRepo.onGetMediaList = (_) async => Right((items: second, total: 4));

      await notifier.loadMore();

      final loaded = notifier.state as MediaListLoaded;
      expect(loaded.items, hasLength(4));
      expect(loaded.hasReachedMax, true);
    });

    test('loadMore does nothing when hasReachedMax', () async {
      final items = [_fakeMedia(1)];
      fakeRepo.onGetMediaList = (_) async => Right((items: items, total: 1));

      await notifier.load();

      final stateBefore = notifier.state;
      await notifier.loadMore();

      expect(notifier.state, equals(stateBefore));
    });
  });

  group('MediaDetailNotifier', () {
    late MediaDetailNotifier notifier;
    late FakeMediaRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeMediaRepository();
      notifier = MediaDetailNotifier(
        getMediaDetail: GetMediaDetail(fakeRepo),
      );
    });

    tearDown(() => notifier.dispose());

    test('initial state is loading', () {
      expect(notifier.state, isA<MediaDetailLoading>());
    });

    test('load emits loaded with media', () async {
      final media = _fakeMedia(1, 'The Matrix');
      fakeRepo.onGetMediaDetail = (_) async => Right(media);

      await notifier.load(1);

      final loaded = notifier.state as MediaDetailLoaded;
      expect(loaded.media.title, 'The Matrix');
      expect(loaded.media.id, 1);
    });

    test('load emits error on failure', () async {
      fakeRepo.onGetMediaDetail =
          (_) async => const Left(ServerFailure(message: 'Not found'));

      await notifier.load(999);

      expect(notifier.state, isA<MediaDetailError>());
      expect((notifier.state as MediaDetailError).message, 'Not found');
    });
  });
}

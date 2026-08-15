import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_detail.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _fakeMedia(int id, [String? title]) => Media(
      id: id,
      title: title ?? 'Media $id',
      year: 2024,
      type: MediaType.video,
      fileSize: 1024,
    );

typedef MediaListCall = ({
  String? type,
  int? year,
  String? q,
  int? limit,
  int? offset,
});

/// Фейк офлайн-кеша без реального IO (path_provider в тестах недоступен).
class FakeOfflineCacheService extends OfflineCacheService {
  FakeOfflineCacheService(Ref ref) : super(ref, 'http://localhost:8080/api');

  List<Media> cachedMedia = [];
  final List<Media> savedMedia = [];

  @override
  Future<void> saveMetadata(Media media) async {
    savedMedia.add(media);
  }

  @override
  Future<List<Media>> getCachedMedia() async => cachedMedia;
}

class FakeMediaRepository implements MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> Function({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  })? onGetMediaList;
  Future<Either<Failure, Media>> Function(int)? onGetMediaDetail;

  final List<MediaListCall> mediaListCalls = [];

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) {
    mediaListCalls.add(
      (type: type, year: year, q: q, limit: limit, offset: offset),
    );
    return onGetMediaList!(
      type: type,
      year: year,
      q: q,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) =>
      onGetMediaDetail!(id);

  @override
  Future<Either<Failure, void>> deleteMedia(int id) async => const Right(null);

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title})>>
      checkHash(String hash) async =>
          const Right((exists: false, mediaId: null, title: null));

  @override
  Future<Either<Failure, List<Artist>>> getArtists() async => const Right([]);

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      const Right(UploadResult(jobId: 0));

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
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
      const Right([]);

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  ) async =>
      Right(_fakeMedia(mediaId));

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async =>
      const Right(
        WatchProgress(
          id: 0,
          userId: 0,
          mediaId: 0,
          position: 0,
        ),
      );

  @override
  Future<Either<Failure, void>> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) async =>
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
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: items, total: 2));

      final result = await container.read(mediaListProvider('video').future);
      expect(result.items, hasLength(2));
      expect(result.total, 2);
    });

    test('passes type, q, limit and offset to the repository', () async {
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          const Right((items: [], total: 0));

      await container.read(mediaListProvider('video').future);

      expect(fakeRepo.mediaListCalls, hasLength(1));
      final call = fakeRepo.mediaListCalls.first;
      expect(call.type, 'video');
      expect(call.q, isNull);
      expect(call.limit, 20);
      expect(call.offset, 0);
    });

    test('loadMore appends items', () async {
      final first = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: first, total: 4));

      await container.read(mediaListProvider('video').future);

      final second = [_fakeMedia(3), _fakeMedia(4)];
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: second, total: 4));

      await container.read(mediaListProvider('video').notifier).loadMore();

      final state = container.read(mediaListProvider('video')).value;
      expect(state?.items, hasLength(4));
      // Второй запрос использует offset = числу уже загруженных элементов.
      expect(fakeRepo.mediaListCalls.last.offset, 2);
      expect(fakeRepo.mediaListCalls.last.limit, 20);
    });

    test('loadMore failure keeps existing items but surfaces the error',
        () async {
      final first = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: first, total: 4));

      await container.read(mediaListProvider('video').future);

      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          const Left(ServerFailure(message: 'Boom'));

      await container.read(mediaListProvider('video').notifier).loadMore();

      final state = container.read(mediaListProvider('video'));
      // Ошибка видна пользователю (ранее copyWithPrevious был no-op)...
      expect(state.hasError, isTrue);
      expect(state.error.toString(), contains('Boom'));
      // ...но уже загруженные элементы сохраняются.
      expect(state.value?.items, hasLength(2));
    });

    test('loadMore result is discarded when query changes', () async {
      final first = [_fakeMedia(1)];
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: first, total: 4));

      await container.read(mediaListProvider('video').future);

      final completer =
          Completer<Either<Failure, ({List<Media> items, int total})>>();
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) =>
          completer.future;

      final loadMoreFuture =
          container.read(mediaListProvider('video').notifier).loadMore();

      // Смена query пересоздаёт build — старый loadMore устарел.
      container.read(searchQueryProvider('video').notifier).state = 'matrix';
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          const Right((items: [], total: 4));
      await container.read(mediaListProvider('video').future);

      completer.complete(const Right((items: [], total: 4)));
      await loadMoreFuture;

      final state = container.read(mediaListProvider('video'));
      // Ответ устаревшего loadMore не дозаписался в новый список.
      expect(state.value?.items, hasLength(0));
      expect(fakeRepo.mediaListCalls.last.q, 'matrix');
    });

    test('loadMore at the end of the list does not make a request',
        () async {
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: [_fakeMedia(1), _fakeMedia(2)], total: 2));

      await container.read(mediaListProvider('video').future);
      await container.read(mediaListProvider('video').notifier).loadMore();

      expect(fakeRepo.mediaListCalls, hasLength(1));
    });

    test('query change does not leave stale loadMore in flight', () async {
      final first = [_fakeMedia(1), _fakeMedia(2)];
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          Right((items: first, total: 4));

      await container.read(mediaListProvider('video').future);

      final completer =
          Completer<Either<Failure, ({List<Media> items, int total})>>();
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) =>
          completer.future;

      final loadMoreFuture =
          container.read(mediaListProvider('video').notifier).loadMore();

      container.read(searchQueryProvider('video').notifier).state = 'matrix';
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          const Right((items: [], total: 4));
      await container.read(mediaListProvider('video').future);

      // Новый список полностью загружен — loadMore с тем же счётчиком
      // больше не должен блокироваться флагом старого запроса.
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          const Right((items: [], total: 4));
      await container.read(mediaListProvider('video').notifier).loadMore();

      completer.complete(const Right((items: [], total: 4)));
      await loadMoreFuture;

      // Старый loadMore отработал без исключений, состояние не испорчено.
      expect(container.read(mediaListProvider('video')).hasError, isFalse);
    });
  });

  group('searchQueryProvider', () {
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

    test('state is scoped per media type', () {
      container.read(searchQueryProvider('video').notifier).state = 'matrix';

      expect(container.read(searchQueryProvider('video')), 'matrix');
      expect(container.read(searchQueryProvider('audio')), '');
    });

    test('query change rebuilds the list with the q parameter', () async {
      fakeRepo.onGetMediaList = ({type, year, q, limit, offset}) async =>
          const Right((items: [], total: 0));

      await container.read(mediaListProvider('video').future);

      container.read(searchQueryProvider('video').notifier).state = 'matrix';
      await container.read(mediaListProvider('video').future);

      expect(fakeRepo.mediaListCalls, hasLength(2));
      expect(fakeRepo.mediaListCalls.first.q, isNull);
      expect(fakeRepo.mediaListCalls.last.q, 'matrix');
      expect(fakeRepo.mediaListCalls.last.offset, 0);
    });
  });

  group('MediaDetailNotifier', () {
    late ProviderContainer container;
    late FakeMediaRepository fakeRepo;
    late FakeOfflineCacheService fakeCache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      fakeRepo = FakeMediaRepository();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mediaRepositoryProvider.overrideWithValue(fakeRepo),
          offlineCacheServiceProvider.overrideWith(
            FakeOfflineCacheService.new,
          ),
          getMediaDetailUseCaseProvider
              .overrideWithValue(GetMediaDetail(fakeRepo)),
        ],
      );
      fakeCache =
          container.read(offlineCacheServiceProvider)
              as FakeOfflineCacheService;
    });

    tearDown(() => container.dispose());

    /// Ждёт достижения целевого состояния детального провайдера.
    /// Первичная загрузка запускается самим провайдером из build()
    /// (Future.microtask) — ручной load() больше не используется.
    Future<void> waitForDetailState(
      int id,
      bool Function(MediaDetailState) done,
    ) async {
      final completer = Completer<void>();
      final sub = container.listen<MediaDetailState>(
        mediaDetailProvider(id),
        (_, next) {
          if (done(next) && !completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
      sub.close();
    }

    test('load emits loaded with media', () async {
      final media = _fakeMedia(1, 'The Matrix');
      fakeRepo.onGetMediaDetail = (_) async => Right(media);

      container.read(mediaDetailProvider(1).notifier);
      await waitForDetailState(1, (s) => s is MediaDetailLoaded);

      final state = container.read(mediaDetailProvider(1));
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'The Matrix');
      // Метаданные сохраняются в офлайн-кеш.
      expect(fakeCache.savedMedia, hasLength(1));
      expect(fakeCache.savedMedia.first.id, 1);
    });

    test('load emits error on failure', () async {
      fakeRepo.onGetMediaDetail =
          (_) async => const Left(ServerFailure(message: 'Not found'));

      container.read(mediaDetailProvider(999).notifier);
      await waitForDetailState(999, (s) => s is MediaDetailError);

      final state = container.read(mediaDetailProvider(999));
      expect(state, isA<MediaDetailError>());
      expect((state as MediaDetailError).message, 'Not found');
    });

    test('load falls back to offline cache on network failure', () async {
      final cached = _fakeMedia(1, 'Cached Title');
      fakeCache.cachedMedia = [cached];
      fakeRepo.onGetMediaDetail =
          (_) async => const Left(NetworkFailure(message: 'Offline'));

      container.read(mediaDetailProvider(1).notifier);
      await waitForDetailState(1, (s) => s is MediaDetailLoaded);

      final state = container.read(mediaDetailProvider(1));
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'Cached Title');
    });

    test('stale load response does not override a newer one', () async {
      final slow = Completer<Either<Failure, Media>>();
      final fast = Completer<Either<Failure, Media>>();

      fakeRepo.onGetMediaDetail = (_) => slow.future;
      final notifier = container.read(mediaDetailProvider(1).notifier);
      final firstLoad = notifier.load(1);

      fakeRepo.onGetMediaDetail = (_) => fast.future;
      final secondLoad = notifier.load(1);

      fast.complete(Right(_fakeMedia(1, 'Fast')));
      await secondLoad;

      slow.complete(Right(_fakeMedia(1, 'Slow')));
      await firstLoad;

      final state = container.read(mediaDetailProvider(1));
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'Fast');
    });

    test('load after provider dispose does not touch state', () async {
      final completer = Completer<Either<Failure, Media>>();
      fakeRepo.onGetMediaDetail = (_) => completer.future;

      final notifier = container.read(mediaDetailProvider(1).notifier);
      final loadFuture = notifier.load(1);

      container.dispose();
      completer.complete(Right(_fakeMedia(1, 'Late')));

      // Не должно бросить и не должно писать в disposed StateNotifier.
      await loadFuture;
    });

    test('refresh keeps state and updates from server', () async {
      final media = _fakeMedia(1, 'Old');
      fakeRepo.onGetMediaDetail = (_) async => Right(media);

      final notifier = container.read(mediaDetailProvider(1).notifier);
      // Первичная загрузка запускается самим провайдером из build()
      // (Future.microtask) — ждём её завершения, а не вызываем load() вручную.
      final loaded = Completer<void>();
      final sub = container.listen<MediaDetailState>(
        mediaDetailProvider(1),
        (_, next) {
          if (next is MediaDetailLoaded && !loaded.isCompleted) {
            loaded.complete();
          }
        },
      );
      await loaded.future;
      sub.close();

      final updated = _fakeMedia(1, 'New').copyWith(
        updatedAt: DateTime.utc(2025),
      );
      fakeRepo.onGetMediaDetail = (_) async => Right(updated);

      await notifier.refresh();

      final state = container.read(mediaDetailProvider(1));
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'New');
    });

    test('refresh failure keeps the current loaded state', () async {
      fakeRepo.onGetMediaDetail =
          (_) async => Right(_fakeMedia(1, 'Old'));

      final notifier = container.read(mediaDetailProvider(1).notifier);
      await notifier.load(1);

      fakeRepo.onGetMediaDetail =
          (_) async => const Left(ServerFailure(message: 'Offline'));

      await notifier.refresh();

      final state = container.read(mediaDetailProvider(1));
      expect(state, isA<MediaDetailLoaded>());
      expect((state as MediaDetailLoaded).media.title, 'Old');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_list.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/download_toggle.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _media(int id) => Media(
      id: id,
      title: 'Media $id',
      year: 2024,
      type: MediaType.audio,
      fileSize: 1024,
    );

/// Кеш-сервис, который фиксирует, какой Media передали в download.
class _RecordingCache extends OfflineCacheService {
  _RecordingCache(super.ref, super.baseUrl);

  Media? downloadedMedia;

  @override
  Future<bool> isCached(int mediaId) async => false;

  @override
  Future<String> download(
    Media media, {
    void Function(int received, int? total)? onProgress,
  }) async {
    downloadedMedia = media;
    return 'local';
  }

  @override
  Future<void> remove(int mediaId) async {}

  @override
  void cancelDownload(int mediaId) {}
}

/// Репозиторий: на первой странице только трек 1, детали по запросу.
class _FakeMediaRepository implements MediaRepository {
  int detailCalls = 0;

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) async {
    detailCalls++;
    return Right(_media(id));
  }

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async {
    return Right((items: [_media(1)], total: 100));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Хост для вызова [toggleDownload] с настоящим [WidgetRef].
class _ToggleHost extends ConsumerWidget {
  const _ToggleHost({required this.mediaId, required this.mediaType});

  final int mediaId;
  final String mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: TextButton(
        onPressed: () =>
            toggleDownload(ref, mediaId: mediaId, mediaType: mediaType),
        child: const Text('toggle'),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingCache cache;
  late _FakeMediaRepository repository;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repository = _FakeMediaRepository();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineCacheServiceProvider.overrideWith(
          (ref) => cache = _RecordingCache(ref, ''),
        ),
        mediaRepositoryProvider.overrideWith((ref) => repository),
        getMediaListProvider.overrideWithValue(GetMediaList(repository)),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpHost(WidgetTester tester, {int mediaId = 2}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: _ToggleHost(mediaId: mediaId, mediaType: 'audio'),
        ),
      ),
    );
    // Предзагружаем список медиа: без читателя провайдер строится только
    // в момент тапа, и трек «не нашёлся» бы в ещё loading-состоянии.
    final mediaList = container.read(mediaListProvider('audio'));
    for (var i = 0; i < 50 && !mediaList.hasValue; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets(
      'downloads via getMediaDetail when track is outside loaded pages',
      (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    expect(repository.detailCalls, 1);
    expect(cache.downloadedMedia, isNotNull);
    // В кеш попадают реальные метаданные, а не заглушка.
    expect(cache.downloadedMedia!.id, 2);
    expect(cache.downloadedMedia!.title, 'Media 2');
    expect(cache.downloadedMedia!.fileSize, 1024);
  });

  testWidgets('uses media from loaded pages without an extra request',
      (tester) async {
    await pumpHost(tester, mediaId: 1);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    expect(repository.detailCalls, 0);
    expect(cache.downloadedMedia?.id, 1);
  });
}

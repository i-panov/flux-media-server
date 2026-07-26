# Phase 4: Video Section UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать Video Section согласно спецификации: горизонтальные ряды категорий (Continue Watching, Recently Added, Favorites, My Collections, All Movies), карточки видео с heart/download иконками, обновлённый detail screen с backdrop и favorite/collection действиями.

**Architecture:** Обновить MediaCard для heart/download. Создать HorizontalRow виджет. Создать use cases для WatchProgress (Continue Watching). Обновить VideoScreen с категориями. Обновить MediaDetailScreen с backdrop, favorite toggle, add to collection.

**Tech Stack:** Flutter, Riverpod, Chopper, auto_route, cached_network_image

---

## Task 1: Добавить API endpoints для Progress

**Files:**
- Modify: `frontend/lib/core/network/api_client.dart`
- Modify: `frontend/lib/features/media/data/datasources/media_remote_datasource.dart`
- Modify: `frontend/lib/features/media/domain/repositories/media_repository.dart`
- Modify: `frontend/lib/features/media/data/repositories/media_repository_impl.dart`

- [ ] **Step 1: Добавить endpoints в ApiClient**

В `api_client.dart`, после endpoint `getScanStatus`, добавить:

```dart
// Progress
@Get(path: '/progress')
Future<Response<List<dynamic>>> getProgress();

@Put(path: '/progress/{mediaId}')
Future<Response<Map<String, dynamic>>> updateProgress(
  @Path('mediaId') int mediaId,
  @Body() Map<String, dynamic> body,
);
```

- [ ] **Step 2: Добавить методы в MediaRemoteDataSource**

В `media_remote_datasource.dart`, добавить методы для получения прогресса:

```dart
/// Fetches watch progress for all media.
Future<List<WatchProgress>> getProgress() async {
  final Response<List<dynamic>> response = await apiClient.getProgress();
  checkResponse(response, 'Failed to fetch progress');
  return (response.body! as List)
      .map((e) => WatchProgress.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Updates watch progress for a media item.
Future<WatchProgress> updateProgress(int mediaId, {int? position, int? duration, bool? completed}) async {
  final Response<Map<String, dynamic>> response = await apiClient.updateProgress(
    mediaId,
    {'position': position, 'duration': duration, 'completed': completed},
  );
  checkResponse(response, 'Failed to update progress');
  return WatchProgress.fromJson(response.body!);
}
```

- [ ] **Step 3: Добавить методы в MediaRepository интерфейс**

В `media_repository.dart`, добавить:

```dart
Future<Either<Failure, List<WatchProgress>>> getProgress();
Future<Either<Failure, WatchProgress>> updateProgress(
  int mediaId, {int? position, int? duration, bool? completed});
```

- [ ] **Step 4: Реализовать в MediaRepositoryImpl**

В `media_repository_impl.dart`, добавить:

```dart
@override
Future<Either<Failure, List<WatchProgress>>> getProgress() async {
  return _wrap<List<WatchProgress>>(
    () => _dataSource.getProgress(),
    'Failed to fetch progress',
  );
}

@override
Future<Either<Failure, WatchProgress>> updateProgress(
  int mediaId, {int? position, int? duration, bool? completed}) async {
  return _wrap<WatchProgress>(
    () => _dataSource.updateProgress(mediaId,
        position: position, duration: duration, completed: completed),
    'Failed to update progress',
  );
}
```

- [ ] **Step 5: Сгенерировать Chopper**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

---

## Task 2: Обновить MediaCard с heart/download иконками

**Files:**
- Modify: `frontend/lib/features/media/presentation/widgets/media_card.dart`

- [ ] **Step 1: Обновить MediaCard**

Добавить:
- `bool isFavorite` параметр
- `VoidCallback? onFavorite` callback
- `bool isDownloaded` параметр (пока заглушка)
- `VoidCallback? onDownload` callback (пока заглушка)
- Overlay с heart иконкой в правом верхнем углу карточки
- Overlay с download иконкой в правом нижнем углу
- Адаптация размера thumbnail для overlay

```dart
class MediaCard extends ConsumerWidget {
  const MediaCard({
    super.key,
    required this.media,
    this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.isDownloaded = false,
    this.onDownload,
  });

  final Media media;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final bool isDownloaded;
  final VoidCallback? onDownload;
```

В build method добавить Positioned overlay для heart и download иконок поверх thumbnail.

---

## Task 3: Создать горизонтальный ряд категорий

**Files:**
- Create: `frontend/lib/features/video/presentation/widgets/horizontal_video_row.dart`

- [ ] **Step 1: Создать HorizontalVideoRow виджет**

```dart
class HorizontalVideoRow extends StatelessWidget {
  const HorizontalVideoRow({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.onItemTap,
    required this.onFavorite,
    required this.isFavoriteMap,
    this.onDownload,
    required this.isDownloadedMap,
  });

  final String title;
  final IconData icon;
  final List<Media> items;
  final VoidCallback onItemTap; // Actually needs to be per-item, will use IndexedWidgetBuilder
  final Function(int) onFavorite;
  final Map<int, bool> isFavoriteMap;
  final Function(int)? onDownload;
  final Map<int, bool> isDownloadedMap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final media = items[index];
              return MediaCard(
                media: media,
                onTap: () => onItemTap(index),
                isFavorite: isFavoriteMap[media.id] ?? false,
                onFavorite: () => onFavorite(media.id),
                isDownloaded: isDownloadedMap[media.id] ?? false,
                onDownload: () => onDownload?.call(media.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
```

---

## Task 4: Создать use case для WatchProgress

**Files:**
- Create: `frontend/lib/features/media/domain/usecases/get_watch_progress.dart`
- Create: `frontend/lib/features/media/presentation/providers/watch_progress_provider.dart`

- [ ] **Step 1: Создать GetWatchProgress use case**

```dart
class GetWatchProgressParams {
  const GetWatchProgressParams();
}

class GetWatchProgress
    extends UseCase<Either<Failure, List<WatchProgress>>, GetWatchProgressParams> {
  GetWatchProgress(this.repository);
  final MediaRepository repository;

  @override
  Future<Either<Failure, List<WatchProgress>>> call(
    GetWatchProgressParams params) async {
    return repository.getProgress();
  }
}
```

- [ ] **Step 2: Создать provider**

```dart
final getWatchProgressProvider = Provider<GetWatchProgress>((ref) {
  return GetWatchProgress(ref.watch(mediaRepositoryProvider));
});

final watchProgressProvider =
    FutureProvider.autoDispose<List<WatchProgress>>((ref) async {
  final getProgress = ref.watch(getWatchProgressProvider);
  final result = await getProgress(const GetWatchProgressParams());
  return result.fold(
    (failure) => throw Exception(failure.message),
    (progress) => progress,
  );
});
```

---

## Task 5: Обновить VideoScreen с категориями

**Files:**
- Modify: `frontend/lib/features/video/presentation/screens/video_screen.dart`

- [ ] **Step 1: Обновить VideoScreen**

Добавить все категории:
1. **Continue Watching** — WatchProgress where completed=false, показывать первые 10, с progress bar overlay
2. **Recently Added** — video media sorted by created_at DESC, показывать первые 10
3. **Favorites** — User favorites where type=video, показывать первые 10
4. **My Collections** — User collections, показывать первые 10
5. **All Movies** — Все video media (текущий grid)

Для Continue Watching:
- Создать отдельный виджет `ContinueWatchingRow` с progress bar overlay на карточке
- Использовать watchProgressProvider для получения прогресса
- Комбинировать с media данными

Для Recently Added:
- Использовать mediaListProvider с type='video', limit=10
- Создать отдельный provider для recently added

Для Favorites:
- Использовать favoritesProvider с type='video'
- Показать только favorite media items

Для My Collections:
- Использовать collectionsProvider
- Создать `CollectionCoverCard` вместо MediaCard

Для All Movies:
- Текущий grid с mediaListProvider

---

## Task 6: Обновить MediaDetailScreen

**Files:**
- Modify: `frontend/lib/features/media/presentation/screens/media_detail_screen.dart`

- [ ] **Step 1: Обновить MediaDetailScreen**

Добавить:
- Backdrop image (большое фоновое изображение за контентом)
- Favorite toggle (heart иконка)
- Add to collection (кнопка)
- Download button (заглушка)
- Использовать AppLocalizations для всех строк

```dart
// Обновить layout:
// 1. Hero backdrop (большое изображение)
// 2. Content overlay (gradient от прозрачного к чёрному)
// 3. Title, year, artist, album, genre
// 4. Description
// 5. Duration
// 6. Action buttons: Play, Favorite (heart), Add to Collection, Download
```

---

## Task 7: Build Verification

- [ ] **Step 1: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: Run analyzer**

Run: `cd frontend && flutter analyze`
Expected: No errors (info-level warnings OK)

- [ ] **Step 3: Build linux**

Run: `cd frontend && flutter build linux --debug`
Expected: Succeeded

- [ ] **Step 4: Commit**

```bash
git add frontend/
git commit -m "feat: Phase 4 — Video Section UI (categories, cards, detail screen)"
```

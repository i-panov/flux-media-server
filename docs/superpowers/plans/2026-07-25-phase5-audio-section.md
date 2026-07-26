# Phase 5: Audio Section UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать Audio Section согласно спецификации: блоки Liked Tracks, Artists, Recently Added. Artist page с track list и "Download All". Track rows с обложкой, названием, артистом, heart/download иконками.

**Architecture:** Обновить AudioScreen с тремя блоками. Создать ArtistPage screen. Создать AudioTrackRow widget. Создать ArtistCard widget. Использовать favoritesProvider для liked tracks.

**Tech Stack:** Flutter, Riverpod, Chopper, auto_route, cached_network_image

---

## Task 1: Создать ArtistCard widget

**Files:**
- Create: `frontend/lib/features/audio/presentation/widgets/artist_card.dart`

- [ ] **Step 1: Создать ArtistCard**

```dart
class ArtistCard extends StatelessWidget {
  const ArtistCard({
    super.key,
    required this.name,
    this.onTap,
  });

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Icon(
              Icons.person,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
```

---

## Task 2: Создать AudioTrackRow widget

**Files:**
- Create: `frontend/lib/features/audio/presentation/widgets/audio_track_row.dart`

- [ ] **Step 1: Создать AudioTrackRow**

```dart
class AudioTrackRow extends StatelessWidget {
  const AudioTrackRow({
    super.key,
    required this.media,
    required this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.isDownloaded = false,
    this.onDownload,
  });

  final Media media;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final bool isDownloaded;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(baseUrlProvider);
    final thumbUrl = '$baseUrl/media/${media.id}/thumb';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundImage: CachedNetworkImageProvider(thumbUrl),
          child: Icon(Icons.music_note),
        ),
        title: Text(media.title),
        subtitle: Text(media.artist ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : null,
                  size: 20),
              onPressed: onFavorite,
            ),
            if (onDownload != null)
              IconButton(
                icon: Icon(isDownloaded ? Icons.check_circle : Icons.cloud_download,
                    color: isDownloaded ? Theme.of(context).colorScheme.primary : null,
                    size: 20),
                onPressed: onDownload,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
```

---

## Task 3: Обновить AudioScreen с блоками

**Files:**
- Modify: `frontend/lib/features/audio/presentation/screens/audio_screen.dart`

- [ ] **Step 1: Обновить AudioScreen**

Добавить:
- **Liked Tracks** — вертикальный список favorite audio items
- **Artists** — горизонтальный скролл уникальных артистов
- **Recently Added** — горизонтальный скролл последних аудио

```dart
// Data fetching:
final audioMediaListState = ref.watch(mediaListProvider);
final favoritesState = ref.watch(favoritesProvider('audio'));
final watchProgressState = ref.watch(watchProgressProvider);

// Extract data:
final audioItems = mediaList.items.where((m) => m.type == 'audio').toList();
final favoriteAudioIds = favorites.where((f) => f.mediaId != null).map((f) => f.mediaId!).toSet();
final likedTracks = audioItems.where((m) => favoriteAudioIds.contains(m.id)).toList();
final artists = audioItems.where((m) => m.artist != null && m.artist!.isNotEmpty).map((m) => m.artist!).toSet().toList();
final recentlyAdded = audioItems.take(10).toList();
```

Layout:
- CustomScrollView с Slivers
- Liked Tracks: SliverList (вертикальный)
- Artists: SliverToBoxAdapter с Horizontal ListView
- Recently Added: SliverToBoxAdapter с Horizontal ListView

---

## Task 4: Создать ArtistPage

**Files:**
- Create: `frontend/lib/features/audio/presentation/screens/artist_page.dart`
- Modify: `frontend/lib/core/router/app_router.dart`

- [ ] **Step 1: Создать ArtistPage**

```dart
@RoutePage()
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({super.key, required this.artistName});

  final String artistName;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  void _toggleFavorite(int mediaId) {
    // TODO: toggle favorite
  }

  void _downloadAll() {
    // TODO: download all
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artistName),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadAll,
          ),
        ],
      ),
      body: state.maybeWhen(
        data: (result) {
          final artistTracks = result.items
              .where((m) => m.artist == widget.artistName)
              .toList();
          
          // Separate liked tracks
          final favoriteIds = ... // from favoritesProvider
          final likedTracks = artistTracks.where((t) => favoriteIds.contains(t.id)).toList();
          final otherTracks = artistTracks.where((t) => !favoriteIds.contains(t.id)).toList();

          return ListView(
            children: [
              if (likedTracks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Liked Tracks', style: Theme.of(context).textTheme.titleMedium),
                ),
                ...likedTracks.map((t) => AudioTrackRow(...)),
              ],
              if (otherTracks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('All Tracks', style: Theme.of(context).textTheme.titleMedium),
                ),
                ...otherTracks.map((t) => AudioTrackRow(...)),
              ],
            ],
          );
        },
        orElse: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
```

- [ ] **Step 2: Добавить маршрут в app_router.dart**

```dart
AutoRoute(page: ArtistPageRoute.page),
```

---

## Task 5: Build Verification

- [ ] **Step 1: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: Run analyzer**

Run: `cd frontend && flutter analyze`
Expected: No errors (info-level warnings OK)

- [ ] **Step 3: Build linux**

Run: `cd frontend && flutter build linux --debug`
Expected: Succeeded

- [ ] **Step 4: Run tests**

Run: `cd frontend && flutter test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add frontend/
git commit -m "feat: Phase 5 — Audio Section UI (artists, liked tracks, artist page)"
```

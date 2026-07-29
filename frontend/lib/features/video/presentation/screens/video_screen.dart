import 'package:auto_route/auto_route.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/watch_progress_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/features/video/presentation/widgets/horizontal_video_row.dart';
import 'package:flux_media_server/features/video/presentation/widgets/continue_watching_row.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:flux_media_server/shared/models/collection.dart';

@RoutePage()
class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({super.key});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ref.read(mediaTypeFilterProvider.notifier).state = 'video';
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      ref.read(mediaListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final baseUrl = ref.watch(baseUrlProvider);
    final isNarrow = MediaQuery.of(context).size.width < 900;

    // Fetch all data in parallel
    final mediaListState = ref.watch(mediaListProvider);
    final watchProgressState = ref.watch(watchProgressProvider);
    final favoritesState = ref.watch(favoritesProvider('video'));
    final collectionsState = ref.watch(collectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.videoTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.upload,
            onPressed: () => context.router.push(UploadRoute(mediaType: 'video')),
          ),
          if (isNarrow)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l.settings,
              onPressed: () => context.router.push(const SettingsRoute()),
            ),
        ],
      ),
      body: _buildBody(
        context: context,
        l: l,
        mediaListState: mediaListState,
        watchProgressState: watchProgressState,
        favoritesState: favoritesState,
        collectionsState: collectionsState,
        baseUrl: baseUrl,
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required AsyncValue<List<WatchProgress>> watchProgressState,
    required AsyncValue<List<Favorite>> favoritesState,
    required AsyncValue<List<Collection>> collectionsState,
    required String baseUrl,
  }) {
    // Show loading state
    if (mediaListState.isLoading ||
        watchProgressState.isLoading ||
        favoritesState.isLoading ||
        collectionsState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error state
    if (mediaListState.hasError ||
        watchProgressState.hasError ||
        favoritesState.hasError ||
        collectionsState.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              mediaListState.error?.toString() ??
                  watchProgressState.error?.toString() ??
                  favoritesState.error?.toString() ??
                  collectionsState.error?.toString() ??
                  'Unknown error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(mediaListProvider);
                ref.invalidate(watchProgressProvider);
                ref.invalidate(favoritesProvider);
                ref.invalidate(collectionsProvider);
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }

    // Get data
    final mediaList = mediaListState.valueOrNull ?? MediaListResult(items: const <Media>[].toIList(), total: 0);
    final watchProgress = watchProgressState.valueOrNull ?? [];
    final favorites = favoritesState.valueOrNull ?? [];
    final collections = collectionsState.valueOrNull ?? [];

    // Filter incomplete watch progress
    final incompleteProgress = watchProgress
        .where((p) => !p.completed)
        .take(10)
        .toList();

    // Get favorite media IDs
    final favoriteMediaIds = favorites
        .where((f) => f.mediaId != null)
        .map((f) => f.mediaId!)
        .toSet();

    // Recently Added section
    final recentlyAdded = mediaList.items.take(10).toList();

    // Filter favorites from media items
    final favoriteVideos = mediaList.items
        .where((m) => favoriteMediaIds.contains(m.id))
        .take(10)
        .toList();

    // Build continue watching items with progress
    final continueWatchingItems = incompleteProgress.map((p) {
      final media = mediaList.items.firstWhere(
        (m) => m.id == p.mediaId,
        orElse: () => Media(
          id: p.mediaId,
          title: 'Unknown',
          year: 0,
          type: 'video',
          filePath: '',
          fileSize: 0,
          description: null,
          duration: p.duration,
          thumbnailUrl: null,
          artist: null,
          album: null,
          genre: null,
          metadata: null,
        ),
      );
      return (media, p);
    }).toList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Continue Watching section
        if (continueWatchingItems.isNotEmpty)
          SliverToBoxAdapter(
            child: ContinueWatchingRow(
              items: continueWatchingItems,
              onItemTapped: (id) =>
                  context.router.push(MediaDetailRoute(mediaId: id)),
              isFavoriteMap: {
                for (var id in favoriteMediaIds) id: true
              },
              onFavoriteToggled: (id) => _toggleFavorite(id),
              isDownloadedMap: const {},
              onDownloadToggled: (id) => _toggleDownload(id),
            ),
          ),

        // Recently Added section
        if (recentlyAdded.isNotEmpty)
          SliverToBoxAdapter(
            child: HorizontalVideoRow(
              title: l.recentlyAdded,
              icon: Icons.new_releases,
              items: recentlyAdded,
              onItemTapped: (id) =>
                  context.router.push(MediaDetailRoute(mediaId: id)),
              isFavoriteMap: {
                for (var id in favoriteMediaIds) id: true
              },
              onFavoriteToggled: (id) => _toggleFavorite(id),
              isDownloadedMap: const {},
              onDownloadToggled: (id) => _toggleDownload(id),
            ),
          ),

        // Favorites section
        if (favoriteVideos.isNotEmpty)
          SliverToBoxAdapter(
            child: HorizontalVideoRow(
              title: l.favorites,
              icon: Icons.favorite,
              items: favoriteVideos,
              onItemTapped: (id) =>
                  context.router.push(MediaDetailRoute(mediaId: id)),
              isFavoriteMap: {
                for (var id in favoriteMediaIds) id: true
              },
              onFavoriteToggled: (id) => _toggleFavorite(id),
              isDownloadedMap: const {},
              onDownloadToggled: (id) => _toggleDownload(id),
            ),
          ),

        // Collections section
        if (collections.isNotEmpty)
          SliverToBoxAdapter(
            child: _CollectionsRow(
              collections: collections,
              onItemTapped: (id) {
                final collection = collections.firstWhere((c) => c.id == id);
                context.router.push(CollectionDetailRoute(collection: collection));
              },
            ),
          ),

        // All Movies section
        if (mediaList.items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.video_library_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    l.noMediaFound,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    (MediaQuery.of(context).size.width / 180).floor().clamp(2, 6),
                childAspectRatio: 0.7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final media = mediaList.items[index];
                  return MediaCard(
                    media: media,
                    onTap: () =>
                        context.router.push(MediaDetailRoute(mediaId: media.id)),
                    isFavorite: favoriteMediaIds.contains(media.id),
                    onFavorite: () => _toggleFavorite(media.id),
                    isDownloaded: false,
                    onDownload: () => _toggleDownload(media.id),
                  );
                },
                childCount: mediaList.items.length,
              ),
            ),
          ),
      ],
    );
  }

  void _toggleFavorite(int mediaId) {
    ref.read(favoriteToggleProvider(mediaId).notifier).toggle(mediaId, 'video');
  }

  void _toggleDownload(int mediaId) {
    final downloadState = ref.read(downloadNotifierProvider(mediaId));
    if (downloadState is DownloadDownloaded) {
      ref.read(downloadNotifierProvider(mediaId).notifier).remove(mediaId);
    } else if (downloadState is! DownloadDownloading) {
      // Need media object — find from list
      final mediaList = ref.read(mediaListProvider).valueOrNull;
      if (mediaList != null) {
        final media = mediaList.items.firstWhere(
          (m) => m.id == mediaId,
          orElse: () => Media(
            id: mediaId, title: '', year: 0, type: 'video',
            filePath: '', fileSize: 0, description: null, duration: null,
            thumbnailUrl: null, artist: null, album: null, genre: null, metadata: null,
          ),
        );
        ref.read(downloadNotifierProvider(mediaId).notifier).download(media);
      }
    }
  }
}

/// A row showing collection covers.
class _CollectionsRow extends StatelessWidget {
  const _CollectionsRow({
    required this.collections,
    required this.onItemTapped,
  });

  final List<Collection> collections;
  final ValueChanged<int> onItemTapped;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.folder,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(l.myCollections,
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: collections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final collection = collections[index];
              return GestureDetector(
                onTap: () => onItemTapped(collection.id),
                child: Container(
                  width: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_library,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 4),
                      Text(
                        collection.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

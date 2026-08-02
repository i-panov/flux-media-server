import 'package:auto_route/auto_route.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/artist_card.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  static const _mediaType = 'audio';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
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
      ref.read(mediaListProvider(_mediaType).notifier).loadMore();
    }
  }

  void _playTrack(List<Media> queue, int index) {
    ref.read(playQueueProvider.notifier).setQueue(queue, startIndex: index);
  }

  void _addToQueue(Media media) {
    ref.read(playQueueProvider.notifier).enqueue(media);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.addedToQueue)),
    );
  }

  void _toggleFavorite(int mediaId) {
    ref.read(favoriteToggleProvider(mediaId).notifier).toggle(mediaId, 'audio');
  }

  void _toggleDownload(int mediaId) {
    final downloadState = ref.read(downloadNotifierProvider(mediaId));
    if (downloadState is DownloadDownloaded) {
      ref.read(downloadNotifierProvider(mediaId).notifier).remove(mediaId);
    } else if (downloadState is! DownloadDownloading) {
      final mediaList = ref.read(mediaListProvider(_mediaType)).valueOrNull;
      if (mediaList != null) {
        final media = mediaList.items.firstWhere(
          (m) => m.id == mediaId,
          orElse: () => Media(
            id: mediaId, title: '', year: null, type: 'audio',
            filePath: '', fileSize: 0, description: null, duration: null,
            thumbnailUrl: null, artist: null, album: null, genre: null, metadata: null,
          ),
        );
        ref.read(downloadNotifierProvider(mediaId).notifier).download(media);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isNarrow = MediaQuery.of(context).size.width < 900;

    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final favoritesState = ref.watch(favoritesProvider('audio'));

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        title: Text(l.audioTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.upload,
            onPressed: () => context.router.push(UploadRoute(mediaType: 'audio')),
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
        favoritesState: favoritesState,
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required AsyncValue<List<Favorite>> favoritesState,
  }) {
    if (mediaListState.isLoading) {
      return _buildSkeletonList(context);
    }
    if (favoritesState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (mediaListState.hasError || favoritesState.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              mediaListState.error?.toString() ??
                  favoritesState.error?.toString() ??
                  'Unknown error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(mediaListProvider(_mediaType));
                ref.invalidate(favoritesProvider);
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }

    final mediaList = mediaListState.valueOrNull ?? MediaListResult(items: <Media>[].toIList(), total: 0);
    final favorites = favoritesState.valueOrNull ?? [];

    if (mediaList.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l.noMediaFound,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final favoriteMediaIds = favorites
        .where((Favorite f) => f.mediaId != null)
        .map((Favorite f) => f.mediaId!)
        .toSet();

    final likedTracks = mediaList.items
        .where((Media m) => favoriteMediaIds.contains(m.id))
        .take(10)
        .toList();

    final artists = mediaList.items
        .where((Media m) => m.artist != null && m.artist!.isNotEmpty)
        .map((Media m) => m.artist!)
        .toSet()
        .toList()
          ..sort();

    final allTracks = mediaList.items.toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(mediaListProvider(_mediaType));
        ref.invalidate(favoritesProvider);
        await ref.watch(mediaListProvider(_mediaType).future);
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchBar(
                hintText: l.searchMedia,
                leading: const Icon(Icons.search),
                onChanged: (value) {
                  if (value.isEmpty) {
                    ref.read(searchQueryProvider.notifier).state = '';
                  }
                },
                onSubmitted: (value) =>
                    ref.read(searchQueryProvider.notifier).state = value,
              ),
            ),
          ),
          if (likedTracks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.favorite,
                title: l.likedTracks,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AudioTrackRow(
                  media: likedTracks[index],
                  isFavorite: true,
                  onPlay: () => _playTrack(likedTracks, index),
                  onFavorite: () => _toggleFavorite(likedTracks[index].id),
                  onDownload: () => _toggleDownload(likedTracks[index].id),
                  onAddToQueue: () => _addToQueue(likedTracks[index]),
                  onAddToCollection: () => showAddToCollectionDialog(
                      context, ref, likedTracks[index].id),
                  onEditMetadata: () =>
                      showEditMetadataDialog(context, ref, likedTracks[index]),
                  onDetails: () => context.router
                      .push(MediaDetailRoute(mediaId: likedTracks[index].id)),
                ),
                childCount: likedTracks.length,
              ),
            ),
          ],
          if (artists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.people,
                title: l.artists,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: artists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return ArtistCard(
                      name: artist,
                      onTap: () =>
                          context.router.push(ArtistRoute(artistName: artist)),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.music_note,
              title: l.allTracks,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => AudioTrackRow(
                media: allTracks[index],
                isFavorite: favoriteMediaIds.contains(allTracks[index].id),
                onPlay: () => _playTrack(allTracks, index),
                onFavorite: () => _toggleFavorite(allTracks[index].id),
                onDownload: () => _toggleDownload(allTracks[index].id),
                onAddToQueue: () => _addToQueue(allTracks[index]),
                onAddToCollection: () => showAddToCollectionDialog(
                    context, ref, allTracks[index].id),
                onEditMetadata: () =>
                    showEditMetadataDialog(context, ref, allTracks[index]),
                onDetails: () => context.router
                    .push(MediaDetailRoute(mediaId: allTracks[index].id)),
              ),
              childCount: allTracks.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const SkeletonWidget(width: 48, height: 48, borderRadius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonWidget(height: 14, width: double.infinity),
                  const SizedBox(height: 6),
                  const SkeletonWidget(height: 10, width: 120),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
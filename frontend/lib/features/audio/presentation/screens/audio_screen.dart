import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/artist_card.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final baseUrl = ref.watch(baseUrlProvider);
    final isNarrow = MediaQuery.of(context).size.width < 900;

    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final favoritesState = ref.watch(favoritesProvider('audio'));

    return Scaffold(
      appBar: AppBar(
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
        baseUrl: baseUrl,
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required AsyncValue<List<Favorite>> favoritesState,
    required String baseUrl,
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
        .toList();

    final artists = mediaList.items
        .where((Media m) => m.artist != null && m.artist!.isNotEmpty)
        .map((Media m) => m.artist!)
        .toSet()
        .toList()
          ..sort();

    final recentlyAdded = mediaList.items.take(10).toList();

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
                onSubmitted: (value) => ref.read(searchQueryProvider.notifier).state = value,
              ),
          ),
        ),
        if (likedTracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.favorite, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l.likedTracks, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        if (likedTracks.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final media = likedTracks[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: AudioTrackRow(
                    media: media,
                    onTap: () => context.router.push(MediaDetailRoute(mediaId: media.id)),
                    isFavorite: true,
                    onFavorite: () => _toggleFavorite(media.id),
                    isDownloaded: false,
                    onDownload: () => _toggleDownload(media.id),
                  ),
                );
              },
              childCount: likedTracks.length,
            ),
          ),
        if (artists.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.people, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(l.artists, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                SizedBox(
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
                        onTap: () => context.router.push(ArtistRoute(artistName: artist)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        if (recentlyAdded.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.new_releases, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(l.recentlyAdded, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                SizedBox(
                  height: 240,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: recentlyAdded.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final media = recentlyAdded[index];
                      return SizedBox(
                        width: 160,
                        child: MediaCard(
                          media: media,
                          onTap: () => context.router.push(MediaDetailRoute(mediaId: media.id)),
                          isFavorite: favoriteMediaIds.contains(media.id),
                          onFavorite: () => _toggleFavorite(media.id),
                          isDownloaded: false,
                          onDownload: () => _toggleDownload(media.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
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
            id: mediaId, title: '', year: 0, type: 'audio',
            filePath: '', fileSize: 0, description: null, duration: null,
            thumbnailUrl: null, artist: null, album: null, genre: null, metadata: null,
          ),
        );
        ref.read(downloadNotifierProvider(mediaId).notifier).download(media);
      }
    }
  }
}

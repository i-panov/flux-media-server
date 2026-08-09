import 'package:auto_route/auto_route.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
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
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({
    required this.artistId,
    required this.artistName,
    super.key,
  });

  final int artistId;
  final String artistName;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  static const _mediaType = 'audio';
  final ScrollController _scrollController = ScrollController();
  bool _downloadingAll = false;
  int _downloadedCount = 0;
  int _downloadTotal = 0;

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
    final position = _scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent * 0.8) {
      ref.read(mediaListProvider(_mediaType).notifier).loadMore();
    }
  }

  void _toggleFavorite(int mediaId) {
    ref.read(favoriteToggleProvider(mediaId).notifier).toggle();
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

  Future<void> _downloadAll(List<Media> tracks) async {
    if (tracks.isEmpty) return;

    setState(() {
      _downloadingAll = true;
      _downloadedCount = 0;
      _downloadTotal = tracks.length;
    });

    var downloaded = 0;
    for (final track in tracks) {
      if (!mounted) break;
      final cached =
          await ref.read(offlineCacheServiceProvider).isCached(track.id);
      if (!cached) {
        await ref
            .read(downloadNotifierProvider(track.id).notifier)
            .download(track);
      }
      if (!mounted) break;
      downloaded++;
      setState(() => _downloadedCount = downloaded);
    }

    if (mounted) {
      setState(() => _downloadingAll = false);
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.downloadedOfTotalTracks(downloaded, _downloadTotal),
          ),
        ),
      );
    }
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
            id: mediaId,
            title: '',
            type: MediaType.audio,
            fileSize: 0,
          ),
        );
        ref.read(downloadNotifierProvider(mediaId).notifier).download(media);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final favoritesState = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artistName),
        actions: [
          if (_downloadingAll)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text('$_downloadedCount/$_downloadTotal'),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: l.download,
              onPressed: _buildDownloadAll(mediaListState),
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

  VoidCallback? _buildDownloadAll(AsyncValue<MediaListResult> mediaListState) {
    if (mediaListState.valueOrNull == null) return null;
    final mediaList = mediaListState.value!;
    final tracks = mediaList.items
        .where(
          (m) =>
              m.type == MediaType.audio &&
              m.artists.any((a) => a.id == widget.artistId),
        )
        .toList();
    if (tracks.isEmpty) return null;
    return () => _downloadAll(tracks);
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required AsyncValue<List<Favorite>> favoritesState,
  }) {
    if (mediaListState.isLoading || favoritesState.isLoading) {
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
                ref
                  ..invalidate(mediaListProvider(_mediaType))
                  ..invalidate(favoritesProvider);
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }

    final mediaList = mediaListState.valueOrNull ??
        MediaListResult(items: <Media>[].toIList(), total: 0);
    final favorites = favoritesState.valueOrNull ?? [];

    final favoriteMediaIds = favorites
        .where((Favorite f) => f.mediaId != null)
        .map((Favorite f) => f.mediaId!)
        .toSet();

    final allTracks = mediaList.items
        .where(
          (Media m) =>
              m.type == MediaType.audio &&
              m.artists.any((a) => a.id == widget.artistId),
        )
        .toList();

    if (allTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l.noTracksFoundForArtist(widget.artistName),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final likedTracks =
        allTracks.where((Media t) => favoriteMediaIds.contains(t.id)).toList();
    final otherTracks =
        allTracks.where((Media t) => !favoriteMediaIds.contains(t.id)).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(mediaListProvider(_mediaType))
          ..invalidate(favoritesProvider);
        await ref.watch(mediaListProvider(_mediaType).future);
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (likedTracks.isNotEmpty) ...[
            _buildSectionHeader(Icons.favorite, l.likedTracks),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = likedTracks[index];
                  return AudioTrackRow(
                    media: track,
                    isFavorite: true,
                    onPlay: () => _playTrack(likedTracks, index),
                    onFavorite: () => _toggleFavorite(track.id),
                    onDownload: () => _toggleDownload(track.id),
                    onAddToQueue: () => _addToQueue(track),
                    onAddToCollection: () =>
                        showAddToCollectionDialog(context, ref, track.id),
                    onEditMetadata: () =>
                        showEditMetadataDialog(context, ref, track),
                    onDetails: () => context.router.push(
                      MediaDetailRoute(mediaId: track.id),
                    ),
                  );
                },
                childCount: likedTracks.length,
              ),
            ),
          ],
          if (otherTracks.isNotEmpty) ...[
            _buildSectionHeader(Icons.music_note, l.allTracks),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = otherTracks[index];
                  return AudioTrackRow(
                    media: track,
                    onPlay: () => _playTrack(otherTracks, index),
                    onFavorite: () => _toggleFavorite(track.id),
                    onDownload: () => _toggleDownload(track.id),
                    onAddToQueue: () => _addToQueue(track),
                    onAddToCollection: () =>
                        showAddToCollectionDialog(context, ref, track.id),
                    onEditMetadata: () =>
                        showEditMetadataDialog(context, ref, track),
                    onDetails: () => context.router.push(
                      MediaDetailRoute(mediaId: track.id),
                    ),
                  );
                },
                childCount: otherTracks.length,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

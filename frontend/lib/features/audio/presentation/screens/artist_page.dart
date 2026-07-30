import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

@RoutePage()
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({super.key, required this.artistName});

  final String artistName;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  static const _mediaType = 'audio';
  bool _downloadingAll = false;
  int _downloadedCount = 0;
  int _downloadTotal = 0;

  void _toggleFavorite(int mediaId) {
    ref.read(favoriteToggleProvider(mediaId).notifier).toggle(mediaId, 'audio');
  }

  Future<void> _downloadAll() async {
    final mediaList = ref.read(mediaListProvider(_mediaType)).valueOrNull;
    if (mediaList == null) return;

    final tracks = mediaList.items
        .where((m) => m.type == 'audio' && m.artist == widget.artistName)
        .toList();
    if (tracks.isEmpty) return;

    setState(() {
      _downloadingAll = true;
      _downloadedCount = 0;
      _downloadTotal = tracks.length;
    });

    for (final track in tracks) {
      final cached = await ref.read(offlineCacheServiceProvider).isCached(track.id);
      if (!cached) {
        await ref.read(downloadNotifierProvider(track.id).notifier).download(track);
      }
      if (!mounted) break;
      setState(() => _downloadedCount++);
    }

    if (mounted) {
      setState(() => _downloadingAll = false);
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.downloadedOfTotalTracks(_downloadedCount, _downloadTotal))),
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
            id: mediaId, title: '', year: 0, type: 'audio',
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

    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final favoritesState = ref.watch(favoritesProvider('audio'));

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
              onPressed: _downloadAll,
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

    final favoriteMediaIds = favorites
        .where((Favorite f) => f.mediaId != null)
        .map((Favorite f) => f.mediaId!)
        .toSet();

    final allTracks = mediaList.items
        .where((Media m) => m.type == 'audio' && m.artist == widget.artistName)
        .toList();

    if (allTracks.isEmpty) {
      final l = AppLocalizations.of(context)!;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l.noTracksFoundForArtist(widget.artistName),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final likedTracks = allTracks
        .where((Media t) => favoriteMediaIds.contains(t.id))
        .toList();
    final otherTracks = allTracks
        .where((Media t) => !favoriteMediaIds.contains(t.id))
        .toList();

    return ListView(
      children: [
        if (likedTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.favorite, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(l.likedTracks, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ...likedTracks.map((track) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: AudioTrackRow(
                  media: track,
                  onTap: () => context.router.push(MediaDetailRoute(mediaId: track.id)),
                  isFavorite: true,
                  onFavorite: () => _toggleFavorite(track.id),
                  isDownloaded: false,
                  onDownload: () => _toggleDownload(track.id),
                ),
              )),
        ],
        if (otherTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.music_note, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(l.allTracks, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ...otherTracks.map((track) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: AudioTrackRow(
                  media: track,
                  onTap: () => context.router.push(MediaDetailRoute(mediaId: track.id)),
                  isFavorite: false,
                  onFavorite: () => _toggleFavorite(track.id),
                  isDownloaded: false,
                  onDownload: () => _toggleDownload(track.id),
                ),
              )),
        ],
      ],
    );
  }
}

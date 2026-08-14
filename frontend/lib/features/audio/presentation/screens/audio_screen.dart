import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/artist_card.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/download_toggle.dart';
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
    final position = _scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent * 0.8) {
      ref.read(mediaListProvider(_mediaType).notifier).loadMore();
    }
  }

  /// Очередь воспроизведения строится из ВСЕХ загруженных элементов
  /// списка (текущее состояние провайдера), а не из секции.
  void _playTrack(Media media, List<Media> fallbackQueue) {
    final mediaList = ref.read(mediaListProvider(_mediaType)).valueOrNull;
    final queue = mediaList?.items.toList() ?? fallbackQueue;
    final index = queue.indexWhere((m) => m.id == media.id);
    ref
        .read(playQueueProvider.notifier)
        .setQueue(queue, startIndex: index < 0 ? 0 : index);
  }

  void _addToQueue(Media media) {
    ref.read(playQueueProvider.notifier).enqueue(media);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.addedToQueue)),
    );
  }

  void _toggleFavorite(int mediaId) {
    ref.read(favoriteToggleProvider(mediaId).notifier).toggle();
  }

  void _toggleDownload(int mediaId) {
    toggleDownload(ref, mediaId: mediaId, mediaType: _mediaType);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isNarrow = MediaQuery.of(context).size.width < 900;

    // Use select to avoid rebuilding on unrelated state changes.
    final mediaListState = ref.watch(
      mediaListProvider(_mediaType).select(
        (state) => switch (state) {
          AsyncData(:final value) => value,
          _ => null,
        },
      ),
    );
    final favoritesState = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        title: Text(l.audioTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.upload,
            onPressed: () =>
                context.router.push(UploadRoute(mediaType: 'audio')),
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
    required MediaListResult? mediaListState,
    required AsyncValue<List<Favorite>> favoritesState,
  }) {
    final isOffline = ref.watch(isOfflineProvider);

    // Офлайн: сразу показываем скачанные треки из кеша, не ждём
    // провала API (иначе здесь был бы вечный спиннер).
    if (isOffline) {
      final downloadsState = ref.watch(downloadsProvider);
      if (downloadsState.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final downloadedMedia = downloadsState.valueOrNull ?? [];
      final downloadedAudio =
          downloadedMedia.where((m) => m.type == MediaType.audio).toList();
      if (downloadedAudio.isEmpty) {
        return Center(
          child: Text(
            l.noMediaFound,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () async {
          await ref.read(downloadsProvider.notifier).refresh();
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.download,
                title: l.downloads,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AudioTrackRow(
                  media: downloadedAudio[index],
                  onPlay: () =>
                      _playTrack(downloadedAudio[index], downloadedAudio),
                  onDownload: () =>
                      _toggleDownload(downloadedAudio[index].id),
                  onAddToQueue: () => _addToQueue(downloadedAudio[index]),
                  onDetails: () => context.router.push(
                    MediaDetailRoute(mediaId: downloadedAudio[index].id),
                  ),
                ),
                childCount: downloadedAudio.length,
              ),
            ),
          ],
        ),
      );
    }

    if (mediaListState == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (favoritesState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasError = favoritesState.hasError;
    if (hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              favoritesState.error?.toString() ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(favoritesProvider);
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }

    final favorites = favoritesState.valueOrNull ?? [];

    // Downloaded tracks — shown as a section when online.
    final downloadsState = ref.watch(downloadsProvider);
    final downloadedMedia = downloadsState.valueOrNull ?? [];
    final downloadedAudio =
        downloadedMedia.where((m) => m.type == MediaType.audio).toList();

    // Use the already-selected media list.
    final mediaList = mediaListState;

    // Offline + no server media → show downloaded only.
    if (mediaList.items.isEmpty && downloadedAudio.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 64,
              color: Colors.grey,
            ),
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

    // Collect unique artists from all media items.
    final artistMap = <int, String>{};
    for (final m in mediaList.items) {
      for (final a in m.artists) {
        artistMap.putIfAbsent(a.id, () => a.name);
      }
    }
    final artists = artistMap.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    final allTracks = mediaList.items.toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(mediaListProvider(_mediaType))
          ..invalidate(favoritesProvider);
        // Ошибка уже отражена в состоянии провайдера.
        try {
          await ref.watch(mediaListProvider(_mediaType).future);
        } catch (_) {}
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
                    ref.read(searchQueryProvider('audio').notifier).state = '';
                  }
                },
                onSubmitted: (value) {
                  ref.read(searchQueryProvider('audio').notifier).state = value;
                },
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
                  onPlay: () => _playTrack(likedTracks[index], allTracks),
                  onFavorite: () => _toggleFavorite(likedTracks[index].id),
                  onDownload: () => _toggleDownload(likedTracks[index].id),
                  onAddToQueue: () => _addToQueue(likedTracks[index]),
                  onAddToCollection: () => showAddToCollectionDialog(
                    context,
                    ref,
                    likedTracks[index].id,
                    mediaType: 'audio',
                  ),
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
                      name: artist.value,
                      onTap: () => context.router.push(
                        ArtistRoute(
                          artistId: artist.key,
                          artistName: artist.value,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (downloadedAudio.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.download,
                title: l.downloads,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AudioTrackRow(
                  media: downloadedAudio[index],
                  isFavorite:
                      favoriteMediaIds.contains(downloadedAudio[index].id),
                  onPlay: () => _playTrack(downloadedAudio[index], allTracks),
                  onFavorite: () =>
                      _toggleFavorite(downloadedAudio[index].id),
                  onDownload: () =>
                      _toggleDownload(downloadedAudio[index].id),
                  onAddToQueue: () => _addToQueue(downloadedAudio[index]),
                  onAddToCollection: () => showAddToCollectionDialog(
                    context,
                    ref,
                    downloadedAudio[index].id,
                    mediaType: 'audio',
                  ),
                  onEditMetadata: () => showEditMetadataDialog(
                    context,
                    ref,
                    downloadedAudio[index],
                  ),
                  onDetails: () => context.router.push(
                    MediaDetailRoute(mediaId: downloadedAudio[index].id),
                  ),
                ),
                childCount: downloadedAudio.length,
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
                onPlay: () => _playTrack(allTracks[index], allTracks),
                onFavorite: () => _toggleFavorite(allTracks[index].id),
                onDownload: () => _toggleDownload(allTracks[index].id),
                onAddToQueue: () => _addToQueue(allTracks[index]),
                onAddToCollection: () => showAddToCollectionDialog(
                  context,
                  ref,
                  allTracks[index].id,
                  mediaType: 'audio',
                ),
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

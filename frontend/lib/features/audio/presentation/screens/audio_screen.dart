import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/media_image_url.dart';
import 'package:flux_media_server/features/audio/presentation/utils/play_queue_utils.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/artist_card.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/track_actions_mixin.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/artists_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_actions.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_list_scaffold.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class AudioScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen>
    with TrackActionsMixin<AudioScreen>, MediaListSearchMixin<AudioScreen> {
  bool _showAllLiked = false;

  @override
  String get mediaType => 'audio';

  /// Очередь строится из всего загруженного списка; в офлайне — только из
  /// скачанных (fallbackQueue). Трек вне очереди вставляется в начало,
  /// а не молча заменяется треком №0.
  void _playTrack(Media media, List<Media> fallbackQueue) {
    final isOffline = ref.read(isOfflineProvider);
    final fullQueue = isOffline
        ? null
        : ref.read(mediaListProvider(mediaType)).value?.items.toList();
    final queue = buildPlayQueue(
      media: media,
      fallbackQueue: fallbackQueue,
      fullQueue: fullQueue,
    );
    unawaited(
      ref
          .read(playQueueProvider.notifier)
          .setQueue(queue.queue, startIndex: queue.startIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // select-ы: перестройка только при изменении нужных полей (value
    // сохраняет данные во время pull-to-refresh — нет вечного спиннера).
    final mediaListState = ref.watch(mediaListProvider(mediaType));
    final favoritesHasError = ref.watch(
      favoritesProvider.select((s) => s.hasError),
    );
    final favoritesLoading = ref.watch(
      favoritesProvider.select((s) => s.isLoading),
    );
    // Следим за Set<int>, а не за всем favoritesProvider.
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).value ?? const <int>{};

    return Scaffold(
      appBar: MediaListAppBar(title: l.audioTab, mediaType: mediaType),
      body: _buildBody(
        context: context,
        l: l,
        mediaListState: mediaListState,
        favoritesHasError: favoritesHasError,
        favoritesLoading: favoritesLoading,
        favoriteIds: favoriteIds,
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required bool favoritesHasError,
    required bool favoritesLoading,
    required Set<int> favoriteIds,
  }) {
    final isOffline = ref.watch(isOfflineProvider);
    // has_cover/updated_at приходят только с GET /artists; артисты из
    // треков (m.artists) содержат лишь id+name.
    final artistsState = ref.watch(artistsProvider);

    // Офлайн: сразу показываем скачанные треки из кеша, не ждём
    // провала API (иначе здесь был бы вечный спиннер).
    if (isOffline) {
      final downloadsState = ref.watch(downloadsProvider);
      if (downloadsState.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final downloadedAudio =
          downloadsState.value
              ?.where((m) => m.type == MediaType.audio)
              .toList() ??
          const <Media>[];
      if (downloadedAudio.isEmpty) {
        return Center(
          child: Text(
            l.noMediaFound,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Colors.grey),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () async {
          await ref.read(downloadsProvider.notifier).refresh();
        },
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverSectionHeader(icon: Icons.download, title: l.downloads),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AudioTrackRow(
                  media: downloadedAudio[index],
                  onPlay: () =>
                      _playTrack(downloadedAudio[index], downloadedAudio),
                  onDownload: () => toggleDownloadTrack(
                    ref,
                    mediaType,
                    downloadedAudio[index].id,
                  ),
                  onAddToQueue: () =>
                      addTrackToQueue(ref, downloadedAudio[index]),
                  onChangeCover: () =>
                      changeMediaCover(context, ref, downloadedAudio[index].id),
                  onDelete: () => deleteMediaWithConfirm(
                    context,
                    ref,
                    downloadedAudio[index].id,
                  ),
                ),
                childCount: downloadedAudio.length,
              ),
            ),
          ],
        ),
      );
    }

    final gateWidget = gate(
      favoritesHasError: favoritesHasError,
      favoritesLoading: favoritesLoading,
    );
    if (gateWidget != null) return gateWidget;

    final mediaList = mediaListState.value!;

    // Downloaded tracks — shown as a section when online.
    final downloadsState = ref.watch(downloadsProvider);
    final downloadedAudio =
        downloadsState.value
            ?.where((m) => m.type == MediaType.audio)
            .toList() ??
        const <Media>[];

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
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final likedTracks = mediaList.items
        .where((m) => favoriteIds.contains(m.id))
        .toList();
    final likedToShow = _showAllLiked
        ? likedTracks
        : likedTracks.take(10).toList();

    // Collect unique artists from all media items.
    final artistMap = <int, Artist>{};
    for (final m in mediaList.items) {
      for (final a in m.artists) {
        artistMap.putIfAbsent(a.id, () => a);
      }
    }
    final artists = artistMap.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final allTracks = mediaList.items.toList();

    return searchableList(
      slivers: [
        if (likedToShow.isNotEmpty) ...[
          SliverSectionHeader(
            icon: Icons.favorite,
            title: l.likedTracks,
            trailing: likedTracks.length > 10 && !_showAllLiked
                ? TextButton(
                    onPressed: () => setState(() => _showAllLiked = true),
                    child: Text(l.showAll),
                  )
                : null,
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => AudioTrackRow(
                media: likedToShow[index],
                isFavorite: true,
                onPlay: () => _playTrack(likedToShow[index], allTracks),
                onFavorite: () =>
                    toggleFavoriteTrack(ref, likedToShow[index].id),
                onDownload: () =>
                    toggleDownloadTrack(ref, mediaType, likedToShow[index].id),
                onAddToQueue: () => addTrackToQueue(ref, likedToShow[index]),
                onAddToCollection: () => showAddToCollectionDialog(
                  context,
                  likedToShow[index].id,
                  mediaType: 'audio',
                ),
                onEditMetadata: () =>
                    showEditMetadataDialog(context, ref, likedToShow[index]),
                onChangeCover: () =>
                    changeMediaCover(context, ref, likedToShow[index].id),
                onDelete: () =>
                    deleteMediaWithConfirm(context, ref, likedToShow[index].id),
              ),
              childCount: likedToShow.length,
            ),
          ),
        ],
        if (artists.isNotEmpty) ...[
          SliverSectionHeader(icon: Icons.people, title: l.artists),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: artists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  final serverArtist = artistsState.value
                      ?.where((a) => a.id == artist.id)
                      .firstOrNull;
                  return ArtistCard(
                    name: artist.name,
                    coverUrl: (serverArtist?.hasCover ?? false)
                        ? buildArtistCoverUrl(
                            baseUrl: ref.watch(baseUrlProvider),
                            artistId: artist.id,
                            cacheBust:
                                serverArtist?.updatedAt?.millisecondsSinceEpoch,
                          )
                        : null,
                    onTap: () => context.router.push(
                      ArtistRoute(artistId: artist.id, artistName: artist.name),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (downloadedAudio.isNotEmpty) ...[
          SliverSectionHeader(icon: Icons.download, title: l.downloads),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => AudioTrackRow(
                media: downloadedAudio[index],
                isFavorite: favoriteIds.contains(downloadedAudio[index].id),
                onPlay: () => _playTrack(downloadedAudio[index], allTracks),
                onFavorite: () =>
                    toggleFavoriteTrack(ref, downloadedAudio[index].id),
                onDownload: () => toggleDownloadTrack(
                  ref,
                  mediaType,
                  downloadedAudio[index].id,
                ),
                onAddToQueue: () =>
                    addTrackToQueue(ref, downloadedAudio[index]),
                onAddToCollection: () => showAddToCollectionDialog(
                  context,
                  downloadedAudio[index].id,
                  mediaType: 'audio',
                ),
                onEditMetadata: () => showEditMetadataDialog(
                  context,
                  ref,
                  downloadedAudio[index],
                ),
                onChangeCover: () =>
                    changeMediaCover(context, ref, downloadedAudio[index].id),
                onDelete: () => deleteMediaWithConfirm(
                  context,
                  ref,
                  downloadedAudio[index].id,
                ),
              ),
              childCount: downloadedAudio.length,
            ),
          ),
        ],
        SliverSectionHeader(icon: Icons.music_note, title: l.allTracks),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => AudioTrackRow(
              media: allTracks[index],
              isFavorite: favoriteIds.contains(allTracks[index].id),
              onPlay: () => _playTrack(allTracks[index], allTracks),
              onFavorite: () => toggleFavoriteTrack(ref, allTracks[index].id),
              onDownload: () =>
                  toggleDownloadTrack(ref, mediaType, allTracks[index].id),
              onAddToQueue: () => addTrackToQueue(ref, allTracks[index]),
              onAddToCollection: () => showAddToCollectionDialog(
                context,
                allTracks[index].id,
                mediaType: 'audio',
              ),
              onEditMetadata: () =>
                  showEditMetadataDialog(context, ref, allTracks[index]),
              onChangeCover: () =>
                  changeMediaCover(context, ref, allTracks[index].id),
              onDelete: () =>
                  deleteMediaWithConfirm(context, ref, allTracks[index].id),
            ),
            childCount: allTracks.length,
          ),
        ),
      ],
    );
  }
}

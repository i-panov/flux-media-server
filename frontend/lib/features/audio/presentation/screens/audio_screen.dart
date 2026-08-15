import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/audio/presentation/utils/play_queue_utils.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/artist_card.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/track_actions_mixin.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_actions.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen>
    with TrackActionsMixin<AudioScreen> {
  static const _mediaType = 'audio';
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _showAllLiked = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Восстанавливаем строку поиска из провайдера: query живёт в
    // провайдере, а текст поля — в State; при пересоздании экрана
    // (например, после возврата с деталей) поле иначе осталось бы
    // пустым при уже отфильтрованном списке.
    final savedQuery = ref.read(searchQueryProvider(_mediaType));
    if (savedQuery.isNotEmpty) {
      _searchController.text = savedQuery;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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

  /// Очередь строится из всего загруженного списка; в офлайне — только из
  /// скачанных (fallbackQueue). Трек вне очереди вставляется в начало,
  /// а не молча заменяется треком №0.
  void _playTrack(Media media, List<Media> fallbackQueue) {
    final isOffline = ref.read(isOfflineProvider);
    final fullQueue = isOffline
        ? null
        : ref.read(mediaListProvider(_mediaType)).valueOrNull?.items.toList();
    final queue = buildPlayQueue(
      media: media,
      fallbackQueue: fallbackQueue,
      fullQueue: fullQueue,
    );
    ref
        .read(playQueueProvider.notifier)
        .setQueue(queue.queue, startIndex: queue.startIndex);
  }

  /// Live-поиск с debounce 300 мс (как на видео-экране).
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      ref.read(searchQueryProvider(_mediaType).notifier).query = '';
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        ref.read(searchQueryProvider(_mediaType).notifier).query = query;
      });
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(searchQueryProvider(_mediaType).notifier).query = '';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isNarrow = MediaQuery.of(context).size.width < 900;

    // select-ы: перестройка только при изменении нужных полей (valueOrNull
    // сохраняет данные во время pull-to-refresh — нет вечного спиннера).
    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final favoritesHasError =
        ref.watch(favoritesProvider.select((s) => s.hasError));
    final favoritesLoading =
        ref.watch(favoritesProvider.select((s) => s.isLoading));
    // Следим за Set<int>, а не за всем favoritesProvider.
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};

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

    // Офлайн: сразу показываем скачанные треки из кеша, не ждём
    // провала API (иначе здесь был бы вечный спиннер).
    if (isOffline) {
      final downloadsState = ref.watch(downloadsProvider);
      if (downloadsState.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final downloadedAudio = downloadsState.valueOrNull
              ?.where((m) => m.type == MediaType.audio)
              .toList() ??
          const <Media>[];
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
            SliverSectionHeader(icon: Icons.download, title: l.downloads),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AudioTrackRow(
                  media: downloadedAudio[index],
                  onPlay: () =>
                      _playTrack(downloadedAudio[index], downloadedAudio),
                  onDownload: () => toggleDownloadTrack(
                      ref, _mediaType, downloadedAudio[index].id,
                    ),
                  onAddToQueue: () =>
                      addTrackToQueue(ref, downloadedAudio[index]),
                  onChangeCover: () => changeMediaCover(
                    context,
                    ref,
                    downloadedAudio[index].id,
                  ),
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

    if (mediaListState.hasError || favoritesHasError) {
      return ErrorRetryView(
        message: mediaListState.hasError
            ? mediaListState.error?.toString()
            : ref.read(favoritesProvider).error?.toString(),
        onRetry: () {
          ref
            ..invalidate(mediaListProvider(_mediaType))
            ..invalidate(favoritesProvider);
        },
      );
    }

    if (mediaListState.valueOrNull == null || favoritesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final mediaList = mediaListState.valueOrNull!;

    // Downloaded tracks — shown as a section when online.
    final downloadsState = ref.watch(downloadsProvider);
    final downloadedAudio = downloadsState.valueOrNull
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
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final likedTracks =
        mediaList.items.where((Media m) => favoriteIds.contains(m.id)).toList();
    final likedToShow =
        _showAllLiked ? likedTracks : likedTracks.take(10).toList();

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

    // Системный back при активном поиске сначала очищает поиск (возврат
    // к полному списку), а не «проглатывается» корневым PopScope
    // (выход из приложения на мобильных).
    return PopScope(
      canPop: _searchController.text.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSearch();
      },
      child: RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(mediaListProvider(_mediaType))
          ..invalidate(favoritesProvider);
        // Ошибка уже отражена в состоянии провайдера.
        try {
          await ref.read(mediaListProvider(_mediaType).future);
        } catch (_) {}
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchBar(
                controller: _searchController,
                hintText: l.searchMedia,
                leading: const Icon(Icons.search),
                trailing: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) => IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l.cancel,
                      onPressed: value.text.isEmpty ? null : _clearSearch,
                    ),
                  ),
                ],
                onChanged: _onSearchChanged,
              ),
            ),
          ),
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
                  onFavorite: () => toggleFavoriteTrack(
                    ref, likedToShow[index].id,
                  ),
                  onDownload: () => toggleDownloadTrack(
                    ref, _mediaType, likedToShow[index].id,
                  ),
                  onAddToQueue: () =>
                      addTrackToQueue(ref, likedToShow[index]),
                  onAddToCollection: () => showAddToCollectionDialog(
                    context,
                    likedToShow[index].id,
                    mediaType: 'audio',
                  ),
                  onEditMetadata: () =>
                      showEditMetadataDialog(context, ref, likedToShow[index]),
                  onChangeCover: () =>
                      changeMediaCover(context, ref, likedToShow[index].id),
                  onDelete: () => deleteMediaWithConfirm(
                    context,
                    ref,
                    likedToShow[index].id,
                  ),
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
            SliverSectionHeader(icon: Icons.download, title: l.downloads),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AudioTrackRow(
                  media: downloadedAudio[index],
                  isFavorite: favoriteIds.contains(downloadedAudio[index].id),
                  onPlay: () =>
                      _playTrack(downloadedAudio[index], allTracks),
                  onFavorite: () =>
                      toggleFavoriteTrack(ref, downloadedAudio[index].id),
                  onDownload: () => toggleDownloadTrack(
                    ref, _mediaType, downloadedAudio[index].id,
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
                  onChangeCover: () => changeMediaCover(
                    context,
                    ref,
                    downloadedAudio[index].id,
                  ),
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
                onFavorite: () =>
                    toggleFavoriteTrack(ref, allTracks[index].id),
                onDownload: () => toggleDownloadTrack(
                  ref, _mediaType, allTracks[index].id,
                ),
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
        ),
      ),
    );
  }
}

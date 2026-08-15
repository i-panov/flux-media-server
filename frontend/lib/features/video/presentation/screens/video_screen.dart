import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/track_actions_mixin.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/watch_progress_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/features/video/presentation/utils/watch_progress.dart';
import 'package:flux_media_server/features/video/presentation/widgets/horizontal_video_row.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

@RoutePage()
class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({super.key});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen>
    with TrackActionsMixin<VideoScreen> {
  static const _mediaType = 'video';
  final ScrollController _scrollController = ScrollController();

  /// Debounce live-поиска.
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Восстанавливаем строку поиска из провайдера: query живёт в
    // провайдере, а текст поля — в State; при пересоздании экрана
    // поле иначе осталось бы пустым при уже отфильтрованном списке.
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

  /// Live-поиск с debounce 300 мс.
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

    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final isOffline = ref.watch(isOfflineProvider);
    // Ошибки остальных провайдеров — по hasError: перестройка только при
    // переходе в ошибку, а не на каждое обновление данных секций.
    final secondaryHasError = ref.watch(
      watchProgressProvider.select((s) => s.hasError),
    );
    final favoritesHasError =
        ref.watch(favoritesProvider.select((s) => s.hasError));
    final collectionsHasError =
        ref.watch(collectionsProvider.select((s) => s.hasError));
    final hasDownloadedVideo = ref.watch(
      downloadsProvider.select(
        (s) => s.valueOrNull?.any((m) => m.type == MediaType.video) ?? false,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        title: Text(l.videoTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.upload,
            onPressed: () =>
                context.router.push(UploadRoute(mediaType: 'video')),
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
        isOffline: isOffline,
        hasError:
            mediaListState.hasError ||
            secondaryHasError ||
            favoritesHasError ||
            collectionsHasError,
        hasDownloadedVideo: hasDownloadedVideo,
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required bool isOffline,
    required bool hasError,
    required bool hasDownloadedVideo,
  }) {
    // Show loading skeleton only on initial load, not during refresh.
    // valueOrNull вместо value: у AsyncLoading с previous=AsyncError
    // обращение к value бросило бы прошлую ошибку при повторной попытке.
    final isInitialLoad =
        mediaListState.isLoading && mediaListState.valueOrNull == null;
    if (isInitialLoad) {
      return _buildSkeletonGrid(context);
    }

    // Show error state (but not in offline mode — banner is enough)
    if (!isOffline && hasError) {
      return ErrorRetryView(
        message: mediaListState.error?.toString(),
        onRetry: () {
          ref
            ..invalidate(mediaListProvider(_mediaType))
            ..invalidate(watchProgressProvider)
            ..invalidate(favoritesProvider)
            ..invalidate(collectionsProvider);
        },
      );
    }

    final mediaItems =
        mediaListState.valueOrNull?.items.toList() ?? const <Media>[];

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
          ..invalidate(watchProgressProvider)
          ..invalidate(favoritesProvider)
          ..invalidate(collectionsProvider);
        // Ошибка уже отражена в состоянии провайдера.
        try {
          await ref.read(mediaListProvider(_mediaType).future);
        } catch (_) {}
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchBar(
                controller: _searchController,
                hintText: l.searchMedia,
                leading: const Icon(Icons.search),
                trailing: [
                  // ValueListenableBuilder вместо setState на каждый символ.
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
          if (mediaItems.isEmpty && !hasDownloadedVideo)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.video_library_outlined,
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
              ),
            )
          else ...[
            _ContinueWatchingSection(
              mediaItems: mediaItems,
              isOffline: isOffline,
              onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
              onDownloadToggled: (id) =>
                  toggleDownloadTrack(ref, _mediaType, id),
            ),
            _RecentlyAddedSection(
              mediaItems: mediaItems,
              isOffline: isOffline,
              onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
              onDownloadToggled: (id) =>
                  toggleDownloadTrack(ref, _mediaType, id),
            ),
            _FavoritesSection(
              mediaItems: mediaItems,
              isOffline: isOffline,
              onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
              onDownloadToggled: (id) =>
                  toggleDownloadTrack(ref, _mediaType, id),
            ),
            const _CollectionsSection(),
            _DownloadsSection(
              isOffline: isOffline,
              onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
              onDownloadToggled: (id) =>
                  toggleDownloadTrack(ref, _mediaType, id),
            ),
            _AllVideosGrid(
              mediaItems: mediaItems,
              isOffline: isOffline,
              onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
              onDownloadToggled: (id) =>
                  toggleDownloadTrack(ref, _mediaType, id),
            ),
          ],
        ],
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: _videoGridDelegate(),
      itemCount: 12,
      itemBuilder: (context, index) => const Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SkeletonWidget(
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonWidget(height: 14, width: double.infinity),
                  SizedBox(height: 6),
                  SkeletonWidget(height: 10, width: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Адаптивная сетка: вместо фиксированного crossAxisCount —
/// MaxCrossAxisExtent (планшеты не получают слишком много колонок).
SliverGridDelegate _videoGridDelegate() {
  return const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 180,
    childAspectRatio: 0.7,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
  );
}

typedef _IdCallback = void Function(int mediaId);

/// Продолжить просмотр: незавершённый прогресс для элементов текущего
/// списка, отсортирован по updatedAt — свежие сверху.
class _ContinueWatchingSection extends ConsumerStatefulWidget {
  const _ContinueWatchingSection({
    required this.mediaItems,
    required this.isOffline,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
  });

  final List<Media> mediaItems;
  final bool isOffline;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  ConsumerState<_ContinueWatchingSection> createState() =>
      _ContinueWatchingSectionState();
}

class _ContinueWatchingSectionState
    extends ConsumerState<_ContinueWatchingSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final watchProgress =
        ref.watch(watchProgressProvider).valueOrNull ?? const <WatchProgress>[];
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};
    final downloadedIds = ref.watch(
      downloadsProvider.select(
        (s) => s.valueOrNull
                ?.where((m) => m.type == MediaType.video)
                .map((m) => m.id)
                .toSet() ??
            const <int>{},
      ),
    );

    final mediaById = {for (final m in widget.mediaItems) m.id: m};
    final mediaIds = widget.mediaItems.map((m) => m.id).toSet();
    final continueWatching = watchProgress
        .where((p) => mediaIds.contains(p.mediaId))
        .where((p) {
          final duration = p.duration > 0
              ? p.duration
              : (mediaById[p.mediaId]?.duration ?? 0);
          return shouldShowInContinueWatching(
            position: p.position,
            duration: duration,
            completed: p.completed,
          );
        })
        .toList()
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    final items = _showAll ? continueWatching : continueWatching.take(10);
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: HorizontalVideoRow(
        title: l.continueWatching,
        icon: Icons.history,
        items: items.map((p) => mediaById[p.mediaId]!).toList(),
        progressById: {for (final p in items) p.mediaId: p},
        isFavoriteMap: {for (final id in favoriteIds) id: true},
        onFavoriteToggled: widget.isOffline ? null : widget.onFavoriteToggled,
        isDownloadedMap: {for (final id in downloadedIds) id: true},
        onDownloadToggled: widget.onDownloadToggled,
        onItemTapped: (id) =>
            context.router.push(MediaDetailRoute(mediaId: id)),
        trailing: continueWatching.length > 10 && !_showAll
            ? TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(l.showAll),
              )
            : null,
      ),
    );
  }
}

/// Недавно добавленные: первые элементы, не попавшие в «Продолжить просмотр».
class _RecentlyAddedSection extends ConsumerStatefulWidget {
  const _RecentlyAddedSection({
    required this.mediaItems,
    required this.isOffline,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
  });

  final List<Media> mediaItems;
  final bool isOffline;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  ConsumerState<_RecentlyAddedSection> createState() =>
      _RecentlyAddedSectionState();
}

class _RecentlyAddedSectionState extends ConsumerState<_RecentlyAddedSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};
    final downloadedIds = ref.watch(
      downloadsProvider.select(
        (s) => s.valueOrNull
                ?.where((m) => m.type == MediaType.video)
                .map((m) => m.id)
                .toSet() ??
            const <int>{},
      ),
    );
    final mediaIds = widget.mediaItems.map((m) => m.id).toSet();
    final mediaById = {for (final m in widget.mediaItems) m.id: m};
    final continueWatchingIds = ref
        .watch(watchProgressProvider)
        .valueOrNull
        ?.where((p) => mediaIds.contains(p.mediaId))
        .where((p) {
          final duration = p.duration > 0
              ? p.duration
              : (mediaById[p.mediaId]?.duration ?? 0);
          return shouldShowInContinueWatching(
            position: p.position,
            duration: duration,
            completed: p.completed,
          );
        })
        .map((p) => p.mediaId)
        .toSet() ??
        const <int>{};

    final allItems = widget.mediaItems
        .where((m) => !continueWatchingIds.contains(m.id))
        .toList();
    final items = _showAll ? allItems : allItems.take(10).toList();
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: HorizontalVideoRow(
        title: l.recentlyAdded,
        icon: Icons.new_releases,
        items: items,
        isFavoriteMap: {for (final id in favoriteIds) id: true},
        onFavoriteToggled: widget.isOffline ? null : widget.onFavoriteToggled,
        isDownloadedMap: {for (final id in downloadedIds) id: true},
        onDownloadToggled: widget.onDownloadToggled,
        onItemTapped: (id) =>
            context.router.push(MediaDetailRoute(mediaId: id)),
        trailing: allItems.length > 10 && !_showAll
            ? TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(l.showAll),
              )
            : null,
      ),
    );
  }
}

/// Избранные видео, не попавшие в предыдущие секции.
class _FavoritesSection extends ConsumerStatefulWidget {
  const _FavoritesSection({
    required this.mediaItems,
    required this.isOffline,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
  });

  final List<Media> mediaItems;
  final bool isOffline;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  ConsumerState<_FavoritesSection> createState() => _FavoritesSectionState();
}

class _FavoritesSectionState extends ConsumerState<_FavoritesSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};
    final downloadedIds = ref.watch(
      downloadsProvider.select(
        (s) => s.valueOrNull
                ?.where((m) => m.type == MediaType.video)
                .map((m) => m.id)
                .toSet() ??
            const <int>{},
      ),
    );
    final mediaIds = widget.mediaItems.map((m) => m.id).toSet();
    final mediaById = {for (final m in widget.mediaItems) m.id: m};
    final continueWatchingIds = ref
        .watch(watchProgressProvider)
        .valueOrNull
        ?.where((p) => mediaIds.contains(p.mediaId))
        .where((p) {
          final duration = p.duration > 0
              ? p.duration
              : (mediaById[p.mediaId]?.duration ?? 0);
          return shouldShowInContinueWatching(
            position: p.position,
            duration: duration,
            completed: p.completed,
          );
        })
        .map((p) => p.mediaId)
        .toSet() ??
        const <int>{};
    final recentlyAddedIds = widget.mediaItems
        .where((m) => !continueWatchingIds.contains(m.id))
        .take(10)
        .map((m) => m.id)
        .toSet();

    final allItems = widget.mediaItems
        .where(
          (m) =>
              favoriteIds.contains(m.id) &&
              !continueWatchingIds.contains(m.id) &&
              !recentlyAddedIds.contains(m.id),
        )
        .toList();
    final items = _showAll ? allItems : allItems.take(10).toList();
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: HorizontalVideoRow(
        title: l.favorites,
        icon: Icons.favorite,
        items: items,
        isFavoriteMap: {for (final id in favoriteIds) id: true},
        onFavoriteToggled: widget.isOffline ? null : widget.onFavoriteToggled,
        isDownloadedMap: {for (final id in downloadedIds) id: true},
        onDownloadToggled: widget.onDownloadToggled,
        onItemTapped: (id) =>
            context.router.push(MediaDetailRoute(mediaId: id)),
        trailing: allItems.length > 10 && !_showAll
            ? TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(l.showAll),
              )
            : null,
      ),
    );
  }
}

/// Видеоколлекции (только свой тип медиа).
class _CollectionsSection extends ConsumerWidget {
  const _CollectionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = (ref.watch(collectionsProvider).valueOrNull ??
            const <Collection>[])
        .where((c) => c.type == MediaType.video)
        .toList();
    if (collections.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: _CollectionsRow(
        collections: collections,
        onItemTapped: (id) {
          // firstWhere мог бросить StateError — идём циклом.
          for (final c in collections) {
            if (c.id == id) {
              context.router.push(CollectionDetailRoute(collection: c));
              return;
            }
          }
        },
      ),
    );
  }
}

/// Скачанные видео.
class _DownloadsSection extends ConsumerWidget {
  const _DownloadsSection({
    required this.isOffline,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
  });

  final bool isOffline;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};
    final downloadedVideo = (ref.watch(downloadsProvider).valueOrNull ??
            const <Media>[])
        .where((m) => m.type == MediaType.video)
        .toList();
    if (downloadedVideo.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverSectionHeader(icon: Icons.download, title: l.downloads),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          sliver: SliverGrid(
            gridDelegate: _videoGridDelegate(),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final media = downloadedVideo[index];
                return MediaCard(
                  media: media,
                  onTap: () => context.router
                      .push(MediaDetailRoute(mediaId: media.id)),
                  isFavorite: favoriteIds.contains(media.id),
                  onFavorite: isOffline
                      ? null
                      : () => onFavoriteToggled(media.id),
                  isDownloaded: true,
                  onDownload: () => onDownloadToggled(media.id),
                );
              },
              childCount: downloadedVideo.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// Основная сетка: всё, что не попало в секции выше.
class _AllVideosGrid extends ConsumerWidget {
  const _AllVideosGrid({
    required this.mediaItems,
    required this.isOffline,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
  });

  final List<Media> mediaItems;
  final bool isOffline;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};
    final mediaIds = mediaItems.map((m) => m.id).toSet();
    final mediaById = {for (final m in mediaItems) m.id: m};
    final continueWatchingIds = ref
        .watch(watchProgressProvider)
        .valueOrNull
        ?.where((p) => mediaIds.contains(p.mediaId))
        .where((p) {
          final duration = p.duration > 0
              ? p.duration
              : (mediaById[p.mediaId]?.duration ?? 0);
          return shouldShowInContinueWatching(
            position: p.position,
            duration: duration,
            completed: p.completed,
          );
        })
        .map((p) => p.mediaId)
        .toSet() ??
        const <int>{};
    final recentlyAdded = mediaItems
        .where((m) => !continueWatchingIds.contains(m.id))
        .take(10)
        .toList();
    final recentlyAddedIds = recentlyAdded.map((m) => m.id).toSet();
    final favoriteVideos = mediaItems
        .where(
          (m) =>
              favoriteIds.contains(m.id) &&
              !continueWatchingIds.contains(m.id) &&
              !recentlyAddedIds.contains(m.id),
        )
        .take(10)
        .toList();

    final highlightIds = {
      ...continueWatchingIds,
      ...recentlyAddedIds,
      ...favoriteVideos.map((m) => m.id),
    };
    final gridItems =
        mediaItems.where((m) => !highlightIds.contains(m.id)).toList();
    if (gridItems.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: _videoGridDelegate(),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final media = gridItems[index];
            return MediaCard(
              media: media,
              onTap: () => context.router
                  .push(MediaDetailRoute(mediaId: media.id)),
              isFavorite: favoriteIds.contains(media.id),
              // В офлайне избранное недоступно везде, не только в Downloads.
              onFavorite:
                  isOffline ? null : () => onFavoriteToggled(media.id),
              onDownload: () => onDownloadToggled(media.id),
            );
          },
          childCount: gridItems.length,
        ),
      ),
    );
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
        SectionHeader(icon: Icons.folder, title: l.myCollections),
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
                      Icon(
                        Icons.video_library,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
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

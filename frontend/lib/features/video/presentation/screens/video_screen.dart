import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/widgets/skeleton_media_grid.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/track_actions_mixin.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/watch_progress_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_list_scaffold.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/features/video/presentation/utils/continue_watching.dart';
import 'package:flux_media_server/features/video/presentation/widgets/horizontal_video_row.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// Сколько карточек показывать до кнопки «показать все».
const _sectionLimit = 10;

typedef _IdCallback = void Function(int mediaId);

/// Разобранные данные экрана, общие для всех секций.
///
/// Раньше каждый из пяти виджетов секций заново строил `mediaById`,
/// `favoriteIds`, `downloadedIds` и прогонял фильтр «продолжить просмотр»
/// — четыре полных обхода списка на каждый rebuild.
class _LibraryData {
  const new({
    required this.all,
    required this.mediaById,
    required this.continueWatching,
    required this.favoriteIds,
    required this.downloadedIds,
  });

  factory of(
    List<Media> all,
    ContinueWatching continueWatching,
    Set<int> favoriteIds,
    Set<int> downloadedIds,
  ) => _LibraryData(
    all: all,
    mediaById: {for (final m in all) m.id: m},
    continueWatching: continueWatching,
    favoriteIds: favoriteIds,
    downloadedIds: downloadedIds,
  );

  final List<Media> all;
  final Map<int, Media> mediaById;
  final ContinueWatching continueWatching;
  final Set<int> favoriteIds;
  final Set<int> downloadedIds;

  /// «Недавно добавленные»: всё, кроме «продолжить просмотр».
  ///
  /// Полный список без лимита: первые 10 для показа отрезает
  /// `_VideoSection`, иначе кнопка «показать все» никогда не появлялась.
  List<Media> get recentlyAddedItems => _withoutContinueWatching;

  /// «Избранное»: избранное, что не попало в две секции выше.
  List<Media> get favoriteItems {
    final exclude = {...continueWatching.ids, ...recentlyAddedIds};
    return _exclude(
      all,
      exclude,
    ).where((m) => favoriteIds.contains(m.id)).toList();
  }

  /// Медиа, которые ещё не показаны ни в одной секции, — основа сетки.
  ///
  /// Порядок секций важен: «продолжить просмотр» → «недавно добавленные» →
  /// «избранное». Каждое следующее исключает предыдущие, поэтому элемент
  /// не дублируется в двух секциях. В сетку уходит только то, что секции
  /// не показали в свёрнутом виде (первые 10 каждой).
  List<Media> gridItems() => _exclude(all, {
    ...continueWatching.ids,
    ...recentlyAddedVisibleIds,
    ..._favoriteVisibleSectionIds(),
  });

  List<Media> get _withoutContinueWatching =>
      _exclude(all, continueWatching.ids);

  Set<int> get recentlyAddedIds => {for (final m in recentlyAddedItems) m.id};

  /// Первые 10 «недавно добавленных» — то, что секции показывают
  /// в свёрнутом виде. Остаток уходит в общую сетку.
  Set<int> get recentlyAddedVisibleIds => {
    for (final m in recentlyAddedItems.take(_sectionLimit)) m.id,
  };

  /// Первые 10 «избранных» — то, что секция показывает в свёрнутом виде.
  Set<int> _favoriteVisibleSectionIds() => {
    for (final m in favoriteItems.take(_sectionLimit)) m.id,
  };

  static List<Media> _exclude(List<Media> items, Set<int> exclude) =>
      items.where((m) => !exclude.contains(m.id)).toList();
}

/// Горизонтальная секция со «свернуть/развернуть» и колбэками действий.
class _VideoSection extends ConsumerStatefulWidget {
  const new({
    required this.title,
    required this.icon,
    required this.items,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
    this.isOffline = false,
    this.progressById = const {},
  });

  final String title;
  final IconData icon;
  final List<Media> items;
  final bool isOffline;
  final Map<int, WatchProgress> progressById;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  ConsumerState<_VideoSection> createState() => _VideoSectionState();
}

class _VideoSectionState extends ConsumerState<_VideoSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(_libraryDataProvider);
    final favoriteIds = library.favoriteIds;
    final downloadedIds = library.downloadedIds;
    final split = splitSection(widget.items, _sectionLimit);
    final items = _showAll ? widget.items : split.visible;
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: HorizontalVideoRow(
        title: widget.title,
        icon: widget.icon,
        items: items,
        progressById: widget.progressById,
        isFavoriteMap: {for (final id in favoriteIds) id: true},
        // В офлайне избранное недоступно: обработчик не передаём вовсе.
        onFavoriteToggled: widget.isOffline ? null : widget.onFavoriteToggled,
        isDownloadedMap: {for (final id in downloadedIds) id: true},
        onDownloadToggled: widget.onDownloadToggled,
        onItemTapped: (id) =>
            context.router.push(VideoDetailRoute(mediaId: id)),
        trailing: split.rest.isNotEmpty && !_showAll
            ? TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text(context.l10n.showAll),
              )
            : null,
      ),
    );
  }
}

/// «Продолжить просмотр», посчитанный из списка и прогресса.
///
/// Отдельным провайдером, а не внутри [_libraryDataProvider]: сортировка
/// по свежести — единственное O(n log n) место экрана, и тогл избранного
/// не должен её пересчитывать.
final _continueWatchingProvider = Provider<ContinueWatching>((ref) {
  final mediaList = ref.watch(mediaListProvider('video'));
  final progress = ref.watch(watchProgressProvider).value ?? const [];
  return ContinueWatching.build(
    mediaList.value?.items.toList() ?? const <Media>[],
    progress,
  );
});

/// Секции, вычисленные из списка и прогресса, — общие для всех секций и
/// сетки. Считаются один раз на экран.
final _libraryDataProvider = Provider<_LibraryData>((ref) {
  final mediaList = ref.watch(mediaListProvider('video'));
  final continueWatching = ref.watch(_continueWatchingProvider);
  final favoriteIds =
      ref.watch(favoriteMediaIdsProvider).value ?? const <int>{};
  final downloadedIds = ref.watch(
    downloadsProvider.select(
      (s) =>
          s.value
              ?.where((m) => m.type == MediaType.video)
              .map((m) => m.id)
              .toSet() ??
          const <int>{},
    ),
  );
  return _LibraryData.of(
    mediaList.value?.items.toList() ?? const <Media>[],
    continueWatching,
    favoriteIds,
    downloadedIds,
  );
});

@RoutePage()
class VideoScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen>
    with TrackActionsMixin<VideoScreen>, MediaListSearchMixin<VideoScreen> {
  @override
  String get mediaType => 'video';

  /// Видео-экран перезагружает ещё и прогресс с коллекциями поверх
  /// базовых списка и избранного: секции «продолжить просмотр» и
  /// «коллекции» иначе показали бы stale-данные после pull-to-refresh.
  @override
  void retryMediaList() {
    super.retryMediaList();
    ref
      ..invalidate(watchProgressProvider)
      ..invalidate(collectionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mediaListState = ref.watch(mediaListProvider(mediaType));
    final isOffline = ref.watch(isOfflineProvider);
    // Ошибки остальных провайдеров — по hasError: перестройка только при
    // переходе в ошибку, а не на каждое обновление данных секций.
    final secondaryHasError = ref.watch(
      watchProgressProvider.select((s) => s.hasError),
    );
    final favoritesHasError = ref.watch(
      favoritesProvider.select((s) => s.hasError),
    );
    final collectionsHasError = ref.watch(
      collectionsProvider.select((s) => s.hasError),
    );
    final library = ref.watch(_libraryDataProvider);
    final hasDownloadedVideo = library.downloadedIds.isNotEmpty;

    return Scaffold(
      appBar: MediaListAppBar(title: l.videoTab, mediaType: mediaType),
      body: _buildBody(
        l: l,
        mediaListState: mediaListState,
        isOffline: isOffline,
        hasError:
            mediaListState.hasError ||
            secondaryHasError ||
            favoritesHasError ||
            collectionsHasError,
        library: library,
        hasDownloadedVideo: hasDownloadedVideo,
      ),
    );
  }

  Widget _buildBody({
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required bool isOffline,
    required bool hasError,
    required _LibraryData library,
    required bool hasDownloadedVideo,
  }) {
    // Show loading skeleton only on initial load, not during refresh.
    // value вместо valueOrNull: у AsyncLoading с previous=AsyncError
    // обращение к value бросило бы прошлую ошибку при повторной попытке.
    final isInitialLoad =
        mediaListState.isLoading && mediaListState.value == null;
    if (isInitialLoad) {
      return _buildSkeletonGrid(context);
    }

    // Show error state (but not in offline mode — banner is enough)
    if (!isOffline && hasError) {
      return ErrorRetryView(
        message: mediaListState.error?.toString(),
        onRetry: retryMediaList,
      );
    }

    final mediaItems = library.all;

    // Системный back при активном поиске сначала очищает поиск (возврат
    // к полному списку), а не «проглатывается» корневым PopScope
    // (выход из приложения на мобильных). ListenableBuilder: canPop
    // должен обновляться на каждый символ, а не при rebuild экрана —
    // иначе в окне до debounce back выходит из приложения.
    return searchableList(
      slivers: [
        if (mediaItems.isEmpty && !hasDownloadedVideo)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyLibrary(
              icon: Icons.video_library_outlined,
              message: l.noMediaFound,
            ),
          )
        else ...[
          _VideoSection(
            title: l.continueWatching,
            icon: Icons.history,
            items: [for (final e in library.continueWatching.entries) e.media],
            progressById: library.continueWatching.byId,
            isOffline: isOffline,
            onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
            onDownloadToggled: (id) => toggleDownloadTrack(ref, mediaType, id),
          ),
          _VideoSection(
            title: l.recentlyAdded,
            icon: Icons.new_releases,
            items: library.recentlyAddedItems,
            isOffline: isOffline,
            onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
            onDownloadToggled: (id) => toggleDownloadTrack(ref, mediaType, id),
          ),
          _VideoSection(
            title: l.favorites,
            icon: Icons.favorite,
            items: library.favoriteItems,
            isOffline: isOffline,
            onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
            onDownloadToggled: (id) => toggleDownloadTrack(ref, mediaType, id),
          ),
          const _CollectionsSection(),
          const _DownloadsSection(),
          _AllVideosGrid(
            items: library.gridItems(),
            isOffline: isOffline,
            onFavoriteToggled: (id) => toggleFavoriteTrack(ref, id),
            onDownloadToggled: (id) => toggleDownloadTrack(ref, mediaType, id),
          ),
        ],
      ],
    );
  }

  Widget _buildSkeletonGrid(BuildContext context) {
    return SkeletonMediaGrid(gridDelegate: _videoGridDelegate(), itemCount: 12);
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

/// Пустое состояние библиотеки.
class _EmptyLibrary extends StatelessWidget {
  const new({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// Видеоколлекции (только свой тип медиа).
class _CollectionsSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections =
        (ref.watch(collectionsProvider).value ?? const <Collection>[])
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
              unawaited(
                context.router.push(CollectionDetailRoute(collection: c)),
              );
              return;
            }
          }
        },
      ),
    );
  }
}

/// Скачанные видео.
class _DownloadsSection extends ConsumerWidget with TrackActionsRef {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    final library = ref.watch(_libraryDataProvider);
    final downloadedVideo =
        (ref.watch(downloadsProvider).value ?? const <Media>[])
            .where((m) => m.type == MediaType.video)
            .toList();
    if (downloadedVideo.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverSectionHeader(
          icon: Icons.download,
          title: context.l10n.downloads,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          sliver: SliverGrid(
            gridDelegate: _videoGridDelegate(),
            delegate: SliverChildBuilderDelegate((context, index) {
              final media = downloadedVideo[index];
              return MediaCard(
                media: media,
                onTap: () =>
                    context.router.push(VideoDetailRoute(mediaId: media.id)),
                isFavorite: library.favoriteIds.contains(media.id),
                // В офлайне избранное недоступно везде, не только тут.
                onFavorite: isOffline
                    ? null
                    : () => unawaited(
                        ref
                            .read(favoriteToggleProvider(media.id).notifier)
                            .toggle(),
                      ),
                isDownloaded: true,
                onDownload: () => toggleDownloadTrack(ref, 'video', media.id),
              );
            }, childCount: downloadedVideo.length),
          ),
        ),
      ],
    );
  }
}

/// Основная сетка: всё, что не попало в секции выше.
class _AllVideosGrid extends ConsumerWidget {
  const new({
    required this.items,
    required this.isOffline,
    required this.onFavoriteToggled,
    required this.onDownloadToggled,
  });

  final List<Media> items;
  final bool isOffline;
  final _IdCallback onFavoriteToggled;
  final _IdCallback onDownloadToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final favoriteIds = ref.watch(_libraryDataProvider).favoriteIds;

    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: _videoGridDelegate(),
        delegate: SliverChildBuilderDelegate((context, index) {
          final media = items[index];
          return MediaCard(
            media: media,
            onTap: () =>
                context.router.push(VideoDetailRoute(mediaId: media.id)),
            isFavorite: favoriteIds.contains(media.id),
            // В офлайне избранное недоступно везде, не только в Downloads.
            onFavorite: isOffline ? null : () => onFavoriteToggled(media.id),
            onDownload: () => onDownloadToggled(media.id),
          );
        }, childCount: items.length),
      ),
    );
  }
}

/// A row showing collection covers.
class _CollectionsRow extends StatelessWidget {
  const new({required this.collections, required this.onItemTapped});

  final List<Collection> collections;
  final ValueChanged<int> onItemTapped;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
            separatorBuilder: (_, _) => const SizedBox(width: 8),
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

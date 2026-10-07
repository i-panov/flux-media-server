import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/widgets/search_sliver.dart';

import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_list_state_gate.dart';

// Развилка состояния — часть «набора экрана списка», экспортируем,
// чтобы импорт был один.
export 'package:flux_media_server/features/media/presentation/widgets/media_list_state_gate.dart';

/// Перезагружает список медиа [mediaType] и избранное.
///
/// Вынесено из миксина, чтобы экраны без него (artist_page: свой скролл
/// и явная кнопка «загрузить ещё») делали ровно то же самое.
void retryMediaListOf(WidgetRef ref, String mediaType) {
  ref
    ..invalidate(mediaListProvider(mediaType))
    ..invalidate(favoritesProvider);
}

/// Состояние списка медиа: бесконечный скролл + живой поиск с debounce.
///
/// Три экрана (видео, аудио, артист) держали одинаковые `_scrollController`,
/// `_searchController`, таймер и четыре обработчика — правка поведения
/// debounce требовала синхронных изменений в трёх файлах.
mixin MediaListSearchMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Тип медиа для списка и поискового запроса ('video' / 'audio').
  String get mediaType;

  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

  /// Доля прокрутки, с которой подгружается следующая страница.
  static const _loadMoreAt = 0.8;

  /// Debounce живого поиска: 300 мс.
  static const _debounce = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    // Восстанавливаем строку поиска из провайдера: query живёт в
    // провайдере, а текст поля — в State; при пересоздании экрана поле
    // иначе осталось бы пустым при уже отфильтрованном списке.
    final savedQuery = ref.read(searchQueryProvider(mediaType));
    if (savedQuery.isNotEmpty) searchController.text = savedQuery;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent * _loadMoreAt) {
      unawaited(ref.read(mediaListProvider(mediaType).notifier).loadMore());
    }
  }

  void onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      ref.read(searchQueryProvider(mediaType).notifier).query = '';
      return;
    }
    _searchDebounce = Timer(_debounce, () {
      ref.read(searchQueryProvider(mediaType).notifier).query = query;
    });
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    searchController.clear();
    ref.read(searchQueryProvider(mediaType).notifier).query = '';
  }

  /// Перезагрузить список и связанные с ним данные.
  void retryMediaList() => retryMediaListOf(ref, mediaType);

  /// Каркас списка: живой поиск + pull-to-refresh + бесконечный скролл.
  ///
  /// [slivers] — содержимое под строкой поиска. Обновление ждёт загрузки
  /// первой страницы, но глотает её ошибку: она уже отражена в состоянии
  /// провайдера и показывается экраном.
  Widget searchableList({
    required List<Widget> slivers,
    VoidCallback? onRetry,
  }) {
    final retry = onRetry ?? retryMediaList;
    return SearchPopScope(
      controller: searchController,
      onCleared: clearSearch,
      child: RefreshIndicator(
        onRefresh: () async {
          retry();
          try {
            await ref.read(mediaListProvider(mediaType).future);
          } catch (_) {}
        },
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SearchSliver(
              controller: searchController,
              hintText: context.l10n.searchMedia,
              onChanged: onSearchChanged,
              onCleared: clearSearch,
            ),
            ...slivers,
          ],
        ),
      ),
    );
  }

  /// Развилка «список / загрузка / ошибка»; `null` — рисовать содержимое.
  Widget? gate({
    required bool favoritesHasError,
    required bool favoritesLoading,
  }) => mediaListStateGate(
    ref,
    mediaType: mediaType,
    favoritesHasError: favoritesHasError,
    favoritesLoading: favoritesLoading,
    onRetry: retryMediaList,
  );
}

/// AppBar экрана списка медиа: заголовок вкладки, загрузка, настройки.
///
/// Кнопка настроек прячется на широких экранах — там есть NavigationRail.
class MediaListAppBar extends StatelessWidget implements PreferredSizeWidget {
  const new({required this.title, required this.mediaType, super.key});

  final String title;

  /// Тип медиа для маршрута загрузки ('video' / 'audio').
  final String mediaType;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isNarrow = MediaQuery.of(context).size.width < 900;
    return AppBar(
      // Вкладки уже обозначены подписью и иконкой в навигации.
      leading: const SizedBox.shrink(),
      title: Text(title),
      actions: [
        IconButton(
          icon: const Icon(Icons.upload_outlined),
          tooltip: l.upload,
          onPressed: () =>
              context.router.push(UploadRoute(mediaType: mediaType)),
        ),
        if (isNarrow)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () => context.router.push(const SettingsRoute()),
          ),
      ],
    );
  }
}

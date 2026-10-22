import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/core/utils/scaffold_messenger.dart';
import 'package:flux_media_server/core/widgets/error_retry_view.dart';
import 'package:flux_media_server/core/widgets/skeleton_media_grid.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/utils/bulk_collection_action.dart';
import 'package:flux_media_server/features/collections/presentation/utils/collection_tree.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_media_dialog.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/collection_breadcrumbs.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/collection_grid_tile.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/move_to_collection_dialog.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_selection_provider.dart';
import 'package:flux_media_server/features/trash/presentation/providers/trash_providers.dart';
import 'package:flux_media_server/features/trash/presentation/utils/refresh.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const new({required this.collection, super.key});

  final Collection collection;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  /// Область выделения: выделение внутри коллекции не путается с
  /// выделением в библиотеке (иначе «переместить» относилось бы не к
  /// тому списку).
  String get _selectionScope => 'collection:${widget.collection.id}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final selected = ref.watch(mediaSelectionProvider(_selectionScope)).length;

    return Scaffold(
      appBar: selected > 0
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l.cancel,
                onPressed: () =>
                    ref.read(mediaSelectionProvider(_selectionScope).notifier)
                        .clear(),
              ),
              title: Text(l.selectedCount(selected)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outlined),
                  tooltip: l.moveToCollection,
                  onPressed: () => _moveSelection(context),
                ),
              ],
            )
          : AppBar(
        // Заголовка нет: имя коллекции стоит последним звеном крошек
        // на странице. Одно и то же имя в двух соседних местах
        // («Season 01» в баре и строкой ниже) читалось бы как дубль.
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.addMedia,
            onPressed: () => _showAddMediaDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: l.newSubcollection,
            onPressed: () => _createSubcollection(context),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: l.moveCollection,
            onPressed: () => _moveCollection(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l.deleteCollection,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _Breadcrumbs(collection: widget.collection),
          _SubcollectionsRow(collection: widget.collection),
          Expanded(
            child: _ItemsGrid(
              collection: widget.collection,
              selectionScope: _selectionScope,
            ),
          ),
        ],
      ),
    );
  }

  /// Групповой перенос выделенных элементов в другую коллекцию.
  Future<void> _moveSelection(BuildContext context) async {
    final ids = ref.read(mediaSelectionProvider(_selectionScope)).toList();
    final moved = await moveSelectionToCollection(
      context,
      ref,
      sourceCollectionId: widget.collection.id,
      mediaIds: ids,
      type: widget.collection.type,
    );
    if (!moved || !mounted) return;
    // Элементы ушли из коллекции — список перечитываем, выделение снимаем.
    // При отмене или ошибке выделение остаётся: выбирать заново не нужно.
    ref.invalidate(collectionItemsFullProvider(widget.collection.id));
    ref.read(mediaSelectionProvider(_selectionScope).notifier).clear();
  }

  /// Создание подколлекции: имя спрашиваем, тип наследуем, родитель — мы.
  /// Сервер вернёт 201 с parent_id, список инвалидируем (дети читаются
  /// из общего collectionsProvider).
  Future<void> _createSubcollection(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final name = await _askName(context, l.newSubcollection);
    if (name == null || name.isEmpty || !mounted) return;
    final result = await ref
        .read(collectionsRepositoryProvider)
        .createCollection(
          name: name,
          type: widget.collection.type.name,
          parentId: widget.collection.id,
        );
    if (!mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) => ref.invalidate(collectionsProvider),
    );
  }

  /// Перенос коллекции: цели — то же дерево минус мы и наше поддерево
  /// (иначе цикл; сервер перепроверит и вернёт 400, но лучше не давать
  /// выбрать). -1 из диалога — «В корень».
  Future<void> _moveCollection(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final all = ref.read(collectionsProvider).value;
    // Диалог без данных исключил бы только свой id, а дети остались
    // бы выбираемыми: защита от цикла пропала бы (см. _moveItem).
    if (all == null) {
      ref.invalidate(collectionsProvider);
      if (!context.mounted) return;
      showErrorSnackBar(context, l.failedToLoadCollections);
      return;
    }
    final forest = buildCollectionTree(
      all.where((c) => c.type == widget.collection.type).toList(),
    );
    CollectionNode? self;
    void find(List<CollectionNode> nodes) {
      for (final n in nodes) {
        if (n.collection.id == widget.collection.id) {
          self = n;
          return;
        }
        find(n.children);
        if (self != null) return;
      }
    }

    find(forest);
    final excluded = self == null
        ? {widget.collection.id}
        : subtreeIds(self!);
    final picked = await showMoveToCollectionDialog(
      context,
      ref,
      type: widget.collection.type,
      excludeIds: excluded,
      allowRoot: true,
    );
    if (picked == null || !mounted) return;
    final result = await ref
        .read(collectionsRepositoryProvider)
        .moveCollection(
          widget.collection.id,
          picked == moveToRootId ? null : picked,
        );
    if (!mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        ref.invalidate(collectionsProvider);
        // Экран хранит старый widget.collection (имя/parentId): вместо
        // подписи родителя и крошек — назад к списку с тостом. Тост через
        // глобальный ключ: контекстный снекбар умер бы вместе с экраном.
        final message = l.collectionMoved;
        unawaited(context.router.maybePop());
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
    );
  }

  /// Спрашивает имя одной строкой (создание подколлекции).
  Future<String?> _askName(BuildContext context, String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(ctx)!.create),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    // Счётчики — с сервера (подколлекции + файлы рекурсивно): клиентский
    // подсчёт файлов потребовал бы N+1 запросов. Ошибка stats —
    // fallback на клиентское дерево (без файлов).
    var message = l.deleteCollectionConfirm(widget.collection.name);
    final stats = await ref
        .read(trashRepositoryProvider)
        .getCollectionStats(widget.collection.id);
    stats.fold(
      (_) {
        final all =
            ref.read(collectionsProvider).value ?? const <Collection>[];
        final forest = buildCollectionTree(
          all.where((c) => c.type == widget.collection.type).toList(),
        );
        CollectionNode? self;
        void find(List<CollectionNode> nodes) {
          for (final n in nodes) {
            if (n.collection.id == widget.collection.id) {
              self = n;
              return;
            }
            find(n.children);
            if (self != null) return;
          }
        }

        find(forest);
        final sub = self == null ? 0 : subtreeIds(self!).length - 1;
        if (sub > 0) {
          message = l.deleteCollectionCascadeConfirm(
            widget.collection.name,
            sub,
          );
        }
      },
      (s) {
        // Пустая коллекция — короткий текст без шумных нулей.
        message = (s.subcollections == 0 && s.items == 0)
            ? l.deleteCollectionConfirm(widget.collection.name)
            : l.deleteCollectionTrashConfirm(
                widget.collection.name,
                s.subcollections,
                s.items,
              );
      },
    );
    if (!context.mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteCollection),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await ref
                    .read(collectionsRepositoryProvider)
                    .deleteCollection(widget.collection.id);
                if (context.mounted) {
                  result.fold(
                    (failure) {
                      showErrorSnackBar(
                        context,
                        l.failedToRemove(failure.message),
                      );
                    },
                    (_) {
                      ref.invalidate(collectionsProvider);
                      refreshAfterTrashChange(ref);
                      showTextSnackBar(context, l.movedToTrash);
                      unawaited(context.router.maybePop());
                    },
                  );
                }
              },
              child: Text(
                l.delete,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Диалог выбора медиа для добавления в коллекцию (со списком
  /// медиа типа коллекции и клиентским фильтром-поиском).
  Future<void> _showAddMediaDialog(BuildContext context) {
    return showAddMediaDialog(context, widget.collection);
  }
}

/// Хлебные крошки коллекции: вертикальная цепочка на странице.
///
/// Раньше кнопка «к родителю» стояла в AppBar, но там для цепочки места
/// не хватало — помещался обрывок первого слова. Теперь цепочка
/// на странице, над рядом подколлекций.
class _Breadcrumbs extends ConsumerWidget {
  const new({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Список нужен только для предков. Пока он грузится, цепочка
    // состоит из одной текущей коллекции — имя видно сразу, а не после
    // сетевого ответа. Заголовка в AppBar нет (иначе имя дублировалось
    // бы двумя соседними строками), поэтому прятать его некуда.
    final all = ref.watch(collectionsProvider).value ?? const <Collection>[];

    final crumbs = buildBreadcrumbs(all, collection);
    if (crumbs.isEmpty) return const SizedBox.shrink();

    return CollectionBreadcrumbs(
      crumbs: crumbs,
      onCrumbTapped: (target) {
        if (target.id == collection.id) return;
        unawaited(_openAncestor(context, target));
      },
    );
  }

  /// Переход к предку по крошке.
  ///
  /// Push давал зигзаг: из [глубокая, корень] крошка «корень» клала
  /// третий экран, и системный «назад» возвращал вниз, в глубокую
  /// коллекцию. Поэтому:
  ///
  /// - если предок уже есть в стеке (мы пришли оттуда) — возвращаемся
  ///   к нему через popUntil, стек укорачивается;
  /// - если его в стеке нет (зашли по прямой ссылке) — заменяем текущий
  ///   экран, чтобы стек не рос и «назад» не вёл в потомка.
  Future<void> _openAncestor(BuildContext context, Collection target) async {
    final router = context.router;
    if (collectionIdsInStack(router.stack).contains(target.id)) {
      router.popUntil(
        (route) {
          final settings = route.settings;
          if (settings is! AutoRoutePage) return false;
          final args = settings.routeData.args;
          return args is CollectionDetailRouteArgs &&
              args.collection.id == target.id;
        },
      );
      return;
    }
    await router.replace(CollectionDetailRoute(collection: target));
  }
}

/// Папки-дети текущей коллекции: горизонтальный ряд над сеткой медиа.
/// Пустой ряд не рисуем (SizedBox.shrink), чтобы не было полосы.
class _SubcollectionsRow extends ConsumerWidget {
  const new({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(collectionsProvider).value;
    if (all == null) return const SizedBox.shrink();
    final children = all
        .where(
          (c) => c.parentId == collection.id && c.type == collection.type,
        )
        .toList();
    if (children.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            l.subcollections,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: children.length,
            itemBuilder: (context, index) {
              final child = children[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.folder_outlined, size: 18),
                  label: Text(child.name),
                  onPressed: () => unawaited(
                    context.router.push(
                      CollectionDetailRoute(collection: child),
                    ),
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

/// Сетка медиа — бывшее тело экрана, выделена без изменения логики.
class _ItemsGrid extends ConsumerStatefulWidget {
  const new({required this.collection, required this.selectionScope});

  final Collection collection;

  /// Область выделения: внутри коллекции она своя, иначе выделение
  /// из библиотеки смешивалось бы с выделением здесь.
  final String selectionScope;

  @override
  ConsumerState<_ItemsGrid> createState() => _ItemsGridState();
}

class _ItemsGridState extends ConsumerState<_ItemsGrid> {
  Collection get collection => widget.collection;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final itemsState = ref.watch(
      collectionItemsFullProvider(collection.id),
    );

    return itemsState.when(
        loading: () => _buildSkeletonGrid(context),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(
            collectionItemsFullProvider(widget.collection.id),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l.thisCollectionIsEmpty),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (MediaQuery.of(context).size.width / 180)
                  .floor()
                  .clamp(2, 6),
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final media = items[index];
              return CollectionGridTile(
                media: media,
                selectionScope: widget.selectionScope,
                onTap: () {                  if (media.type == MediaType.audio) {
                    unawaited(
                      context.router.push(AudioPlayerRoute(media: media)),
                    );
                  } else {
                    unawaited(
                      context.router.push(
                        VideoDetailRoute(mediaId: media.id),
                      ),
                    );
                  }
                },
                onRemove: () => _confirmRemoveItem(context, media),
                onMove: () => _moveItem(context, media),
              );
            },
          );
        },
      );
  }

  /// Подтверждение и удаление элемента из коллекции.
  Future<void> _confirmRemoveItem(BuildContext context, Media media) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFromCollection),
        content: Text(media.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(collectionsRepositoryProvider)
        .removeCollectionItem(widget.collection.id, media.id);
    if (!mounted) return;
    result.fold(
      (failure) {
        final l = AppLocalizations.of(context)!;
        showErrorSnackBar(context, l.failedToRemove(failure.message));
      },
      (_) {
        // Оптимистичное обновление списка — без refetch.
        ref
            .read(collectionItemsFullProvider(widget.collection.id).notifier)
            .removeLocal(media.id);
      },
    );
  }

  /// Диалог выбора медиа для добавления в коллекцию уже есть у экрана
  /// (кнопка в AppBar): дубль здесь не нужен.
  /// Подтверждение и перенос элемента в другую коллекцию того же типа.
  Future<void> _moveItem(BuildContext context, Media media) async {
    final l = AppLocalizations.of(context)!;
    // Без загруженного списка клиентская защита (исключение себя)
    // отсутствует — спасает лишь серверный 400. Диалог не открываем,
    // список перезапрашиваем для следующей попытки.
    if (ref.read(collectionsProvider).value == null) {
      ref.invalidate(collectionsProvider);
      if (!context.mounted) return;
      showErrorSnackBar(context, l.failedToLoadCollections);
      return;
    }
    final picked = await showMoveToCollectionDialog(
      context,
      ref,
      type: collection.type,
      excludeIds: {collection.id},
    );
    if (picked == null || picked == moveToRootId || !context.mounted) return;
    final result = await ref
        .read(collectionsRepositoryProvider)
        .moveCollectionItem(collection.id, picked, media.id);
    if (!context.mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        ref
            .read(collectionItemsFullProvider(collection.id).notifier)
            .removeLocal(media.id);
        showTextSnackBar(context, l.itemMoved);
      },
    );
  }

  Widget _buildSkeletonGrid(BuildContext context) {
    final crossAxisCount = (MediaQuery.of(context).size.width / 180)
        .floor()
        .clamp(2, 6);
    return SkeletonMediaGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      // Две «страницы» — столько же плашек, сколько в коллекции.
      itemCount: crossAxisCount * 2,
    );
  }

  /// Удаление коллекции — у экрана (кнопка в AppBar): дубль здесь
  /// не нужен, оставляем только перенос/удаление элементов.
}

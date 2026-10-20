import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/shared/models/collection.dart';

/// Идентификаторы коллекций, открытых в стеке роутера.
///
/// Нужно для перехода по крошке: если предок уже открыт (мы пришли оттуда),
/// возвращаемся к нему через popUntil — иначе push даёт зигзаг: из
/// [глубокая, корень] крошка «корень» клала бы третий экран, и «назад»
/// возвращал бы вниз, в глубокую коллекцию.
List<int> collectionIdsInStack(List<AutoRoutePage<dynamic>> stack) {
  return [
    for (final page in stack)
      if (page.routeData.args is CollectionDetailRouteArgs)
        (page.routeData.args! as CollectionDetailRouteArgs).collection.id,
  ];
}

/// Собирает цепочку крошек от корня до [collection] включительно.
///
/// Цепочка идёт сверху вниз: корень первым, текущая коллекция —
/// последней. Порядок обратный привычному «хлебной крошке в одну
/// строку», но здесь крошки — вертикальным списком на странице, и так
/// они читаются естественно: сверху контекст, снизу текущий уровень.
///
/// Если родитель потерян (удалён или в корзине) — цепочка обрывается
/// на текущей коллекции: вести в никуда нельзя, а показывать
/// несуществующее звено — вводить в заблуждение.
List<Collection> buildBreadcrumbs(List<Collection> all, Collection current) {
  final byId = {for (final c in all) c.id: c};
  final chain = <Collection>[];
  var node = current;
  // visited — защита от цикла в битых данных: сервер циклы не создаёт,
  // но потеряться в них нельзя.
  final visited = <int>{};
  while (visited.add(node.id)) {
    chain.add(node);
    final parentId = node.parentId;
    if (parentId == null) break;
    final parent = byId[parentId];
    if (parent == null) break;
    node = parent;
  }
  return chain.reversed.toList();
}

/// Хлебные крошки коллекции: вертикальный список на странице.
///
/// В AppBar для цепочки не хватало места — там помещался обрывок
/// первого слова. Поэтому крошки живут на странице, над рядом
/// подколлекций: корневой уровень, промежуточные и текущий.
///
/// Каждое звено, кроме текущего, кликабельно — ведёт в ту коллекцию.
class CollectionBreadcrumbs extends StatelessWidget {
  const new({required this.crumbs, required this.onCrumbTapped, super.key});

  /// Цепочка от корня к текущей коллекции.
  final List<Collection> crumbs;

  /// Переход к коллекции из цепочки.
  final void Function(Collection collection) onCrumbTapped;

  @override
  Widget build(BuildContext context) {
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final current = crumbs.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final crumb in crumbs)
          _CrumbTile(
            collection: crumb,
            isCurrent: crumb.id == current.id,
            onTap: () => onCrumbTapped(crumb),
          ),
      ],
    );
  }
}

/// Одно звено цепочки.
class _CrumbTile extends StatelessWidget {
  const new({
    required this.collection,
    required this.isCurrent,
    required this.onTap,
  });

  final Collection collection;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isCurrent
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    if (isCurrent) {
      // Текущий уровень — заголовок, а не ссылка: кликать по нему
      // некуда.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          collection.name,
          style: theme.textTheme.titleMedium?.copyWith(color: color),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // Зона нажатия — 48dp (рекомендация Material), а не 32: по
          // цепочке идут пальцем, и мелкая цель промахивается. Ряд
          // остаётся компактным за счёт вертикальной раскладки.
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(
          Icons.subdirectory_arrow_right,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        label: Text(
          collection.name,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

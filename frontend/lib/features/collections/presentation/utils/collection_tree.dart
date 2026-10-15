import 'package:flux_media_server/shared/models/collection.dart';

/// Узел дерева коллекций: коллекция + непосредственные дети.
class CollectionNode {
  const new({required this.collection, this.children = const []});

  final Collection collection;
  final List<CollectionNode> children;
}

/// Строит лес из плоского списка (`parentId == null` — корни).
/// Сироты (родитель вне списка) — тоже корни: лучше показать, чем потерять.
/// Self-loop (`parentId == id`, битый кеш — сервер такое запрещает) —
/// корень: иначе коллекция невидима нигде. Бесхозные цикловые компоненты
/// (A↔B: оба не корни) — тоже корни: сервер циклы не создаёт, но молча
/// терять данные из вида нельзя; чинится переносом вручную.
/// Циклы в данных рвутся посещённым множеством и не вешают построение.
List<CollectionNode> buildCollectionTree(List<Collection> collections) {
  final byId = {for (final c in collections) c.id: c};
  final childrenOf = <int, List<Collection>>{};
  final roots = <Collection>[];
  for (final c in collections) {
    final parent = c.parentId;
    if (parent == null || parent == c.id || !byId.containsKey(parent)) {
      roots.add(c);
    } else {
      childrenOf.putIfAbsent(parent, () => []).add(c);
    }
  }
  CollectionNode node(Collection c, Set<int> visiting) {
    visiting.add(c.id);
    final kids = <CollectionNode>[];
    for (final k in childrenOf[c.id] ?? const <Collection>[]) {
      if (!visiting.contains(k.id)) kids.add(node(k, {...visiting}));
    }
    return CollectionNode(collection: c, children: kids);
  }

  final forest = [for (final r in roots) node(r, {})];
  // Бесхозные: не достигнуты из корней (цикловой компонент) —
  // показываем корнями с обрезанной по visited цепочкой.
  final reached = <int>{};
  void mark(CollectionNode n) {
    if (!reached.add(n.collection.id)) return;
    n.children.forEach(mark);
  }

  forest.forEach(mark);
  for (final c in collections) {
    if (!reached.contains(c.id)) forest.add(node(c, {}));
  }
  return forest;
}

/// Id коллекции и всего её поддерева (для исключения из пикера
/// перемещения: коллекцию нельзя класть в себя или потомка).
Set<int> subtreeIds(CollectionNode node) {
  final ids = <int>{node.collection.id};
  for (final k in node.children) {
    ids.addAll(subtreeIds(k));
  }
  return ids;
}

/// Плоский список леса в порядке обхода (для пикера): пары
/// (коллекция, глубина).
List<({Collection collection, int depth})> flattenTree(
  List<CollectionNode> forest,
) {
  final out = <({Collection collection, int depth})>[];
  void walk(CollectionNode n, int depth) {
    out.add((collection: n.collection, depth: depth));
    for (final k in n.children) {
      walk(k, depth + 1);
    }
  }

  for (final r in forest) {
    walk(r, 0);
  }
  return out;
}

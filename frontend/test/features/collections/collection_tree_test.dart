import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/collections/presentation/utils/collection_tree.dart';

import '../helpers/collection_helpers.dart';

void main() {
  group('buildCollectionTree', () {
    test('корни и дети раскладываются', () {
      final forest = buildCollectionTree([
        testCollection(1, 'Сериал'),
        testCollection(2, 'Season 01', parentId: 1),
        testCollection(3, 'Season 02', parentId: 1),
        testCollection(4, 'Фильмы'),
      ]);
      expect(forest.map((n) => n.collection.id), [1, 4]);
      expect(
        forest.first.children.map((n) => n.collection.id),
        [2, 3],
      );
    });

    test('сирота с несуществующим родителем — корень, а не потеря', () {
      final forest = buildCollectionTree([
        testCollection(1, 'Сирота', parentId: 999),
      ]);
      expect(forest.map((n) => n.collection.id), [1]);
    });

    test('цикл в данных виден, а не теряется', () {
      final forest = buildCollectionTree([
        testCollection(1, 'A', parentId: 2),
        testCollection(2, 'B', parentId: 1),
      ]);
      // Сервер циклы запрещает (ErrCycle), но битый кеш нельзя молча
      // прятать: обе видны корнями, чинится переносом вручную.
      expect(forest.map((n) => n.collection.id), containsAll([1, 2]));
    });

    test('self-loop — корень', () {
      final forest = buildCollectionTree([
        testCollection(1, 'A', parentId: 1),
      ]);
      expect(forest.map((n) => n.collection.id), [1]);
    });
  });

  group('subtreeIds', () {
    test('возвращает узел и всё поддерево', () {
      final forest = buildCollectionTree([
        testCollection(1, 'Сериал'),
        testCollection(2, 'Season 01', parentId: 1),
        testCollection(3, 'Ep', parentId: 2),
        testCollection(4, 'Фильмы'),
      ]);
      expect(subtreeIds(forest.first), {1, 2, 3});
    });
  });

  group('flattenTree', () {
    test('порядок обхода с глубинами', () {
      final forest = buildCollectionTree([
        testCollection(1, 'Сериал'),
        testCollection(2, 'Season 01', parentId: 1),
      ]);
      final flat = flattenTree(forest);
      expect(
        flat.map((r) => (r.collection.id, r.depth)).toList(),
        [(1, 0), (2, 1)],
      );
    });
  });

  group('buildCollectionTree — глубина и дубли', () {
    test('цепочка 11 уровней не рвётся', () {
      final cols = [
        testCollection(1, 'L0'),
        for (var i = 2; i <= 11; i++) testCollection(i, 'L$i', parentId: i - 1),
      ];
      final forest = buildCollectionTree(cols);
      expect(forest.map((n) => n.collection.id), [1]);
      var node = forest.first;
      for (var i = 2; i <= 11; i++) {
        expect(node.children.map((n) => n.collection.id), [i]);
        node = node.children.first;
      }
    });

    test('дубли id: второй показ скрыт visited-множеством', () {
      final forest = buildCollectionTree([
        testCollection(1, 'A'),
        testCollection(1, 'A-дубль'),
        testCollection(2, 'B', parentId: 1),
      ]);
      final flat = flattenTree(forest);
      final ones = flat.where((r) => r.collection.id == 1).length;
      expect(ones, 2);
      expect(flat.map((r) => r.collection.id), contains(2));
    });

    test('сложный flatten: порядок и глубины', () {
      final forest = buildCollectionTree([
        testCollection(1, 'Сериал'),
        testCollection(2, 'S01', parentId: 1),
        testCollection(3, 'S02', parentId: 1),
        testCollection(4, 'Ep1', parentId: 2),
        testCollection(5, 'Фильмы'),
      ]);
      expect(
        flattenTree(forest).map((r) => (r.collection.id, r.depth)).toList(),
        [(1, 0), (2, 1), (4, 2), (3, 1), (5, 0)],
      );
    });
  });
}

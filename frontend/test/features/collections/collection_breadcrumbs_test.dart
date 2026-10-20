import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/collection_breadcrumbs.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media_type.dart';

/// Тестовый роутер: маршрут коллекции с настоящим экраном.
class _TestRouter extends RootStackRouter {
  new() {
    CollectionDetailRoute.page = PageInfo(
      CollectionDetailRoute.name,
      builder: (data) => const SizedBox.shrink(),
    );
  }

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: CollectionDetailRoute.page, initial: true),
  ];
}

Collection _collection(
  int id, {
  int? parentId,
  String name = 'Col',
}) => Collection(
  id: id,
  userId: 1,
  name: name,
  type: MediaType.video,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  parentId: parentId,
);

void main() {
  group('buildBreadcrumbs', () {
    test('корень — цепочка из одного звена', () {
      final root = _collection(1);

      final crumbs = buildBreadcrumbs([root], root);

      expect(crumbs, hasLength(1));
      expect(crumbs.single.id, 1);
    });

    test('вложенная — цепочка от корня', () {
      final root = _collection(1, name: 'Root');
      final child = _collection(2, parentId: 1, name: 'Child');
      final grand = _collection(3, parentId: 2, name: 'Grand');

      final crumbs = buildBreadcrumbs([root, child, grand], grand);

      expect(crumbs.map((c) => c.id), [1, 2, 3]);
    });

    test('текущая коллекция — последняя', () {
      final root = _collection(1);
      final child = _collection(2, parentId: 1);

      final crumbs = buildBreadcrumbs([root, child], child);

      expect(crumbs.last.id, 2);
    });

    test('потерянный родитель — цепочка обрывается, а не в никуда', () {
      // Родитель удалён или в корзине: показывать несуществующее звено
      // вводит в заблуждение, а вести в никуда нельзя.
      final orphan = _collection(2, parentId: 99);

      final crumbs = buildBreadcrumbs([orphan], orphan);

      expect(crumbs, hasLength(1));
      expect(crumbs.single.id, 2);
    });

    test('цикл в данных не вешает сборку', () {
      // Сервер циклы не создаёт, но в битых данных зависнуть нельзя.
      final a = _collection(1, parentId: 2);
      final b = _collection(2, parentId: 1);

      final crumbs = buildBreadcrumbs([a, b], b);

      expect(crumbs.length, lessThanOrEqualTo(2));
    });
  });

  group('collectionIdsInStack', () {
    testWidgets('собирает id открытых коллекций из стека', (tester) async {
      // От этого зависит переход по крошке: найденный в стеке предок
      // открывается через popUntil (стек укорачивается), ненайденный —
      // через replace (стек не растёт). Иначе push даёт зигзаг: из
      // [глубокая, корень] крошка «корень» клала бы третий экран, и
      // «назад» возвращал бы вниз, в глубокую коллекцию.
      final router = _TestRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router.config(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();

      final root = _collection(1, name: 'Root');
      final child = _collection(2, parentId: 1, name: 'Child');
      unawaited(
        router.push(CollectionDetailRoute(collection: root)),
      );
      await tester.pumpAndSettle();
      unawaited(
        router.push(CollectionDetailRoute(collection: child)),
      );
      await tester.pumpAndSettle();

      expect(collectionIdsInStack(router.stack), [1, 2]);
    });
  });

  group('CollectionBreadcrumbs', () {
    testWidgets('звенья кликабельны, кроме текущего', (tester) async {
      final tapped = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectionBreadcrumbs(
              crumbs: buildBreadcrumbs(
                [_collection(1, name: 'Root'), _collection(2, parentId: 1)],
                _collection(2, parentId: 1),
              ),
              onCrumbTapped: (c) => tapped.add(c.id),
            ),
          ),
        ),
      );

      // Текущая коллекция — заголовок, а не ссылка.
      expect(find.text('Root'), findsOneWidget);
      await tester.tap(find.text('Root'));
      await tester.pump();
      expect(tapped, [1]);
    });

    testWidgets('зона нажатия крошки — не меньше 48dp', (tester) async {
      // По цепочке идут пальцем: мелкая цель (32dp) промахивается.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectionBreadcrumbs(
              crumbs: buildBreadcrumbs(
                [_collection(1, name: 'Root'), _collection(2, parentId: 1)],
                _collection(2, parentId: 1),
              ),
              onCrumbTapped: (_) {},
            ),
          ),
        ),
      );

      final size = tester.getSize(
        find.ancestor(
          of: find.text('Root'),
          matching: find.byType(TextButton),
        ),
      );
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}

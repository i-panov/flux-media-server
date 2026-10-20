import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/screens/collection_detail_screen.dart';
import 'package:flux_media_server/features/trash/data/trash_remote_datasource.dart';
import 'package:flux_media_server/features/trash/presentation/providers/trash_providers.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/collection_helpers.dart';
import '../helpers/fake_repositories.dart';

final _all = [
  testCollection(1, 'Сериал'),
  testCollection(2, 'Season 01', parentId: 1),
  testCollection(3, 'Season 02', parentId: 1),
  testCollection(4, 'Фильмы'),
];

/// Тестовый роутер: деталь коллекции — настоящий экран с фиксированной
/// коллекцией, остальное не нужно (паттерн main_screen_test).
class _TestRouter extends RootStackRouter {
  new({required Collection collection}) {
    CollectionDetailRoute.page = PageInfo(
      CollectionDetailRoute.name,
      builder: (data) => CollectionDetailScreen(collection: collection),
    );
  }

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: CollectionDetailRoute.page, initial: true),
  ];
}

Future<FakeTrashRepository> pumpDetail(
  WidgetTester tester, {
  required Collection collection,
  /// Список коллекций для провайдера. `null` — список ещё грузится
  /// (данных нет): так проверяется, что имя коллекции видно до ответа
  /// сети.
  List<Collection>? collectionsOverride,
  /// Не переопределять провайдер списка вовсе: он сам ходит в репозиторий
  /// и первым кадром находится в состоянии загрузки.
  bool useRealCollectionsProvider = false,
  /// Ждать ли загрузки данных. `false` — остановиться на первом кадре:
  /// так проверяется состояние «список ещё едет».
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fake = FakeCollectionsRepository()
    ..onGetCollections = (() async => Right(_all))
    ..onGetItemsFull = ((_) async => const Right([]));
  final trashFake = FakeTrashRepository();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      baseUrlProvider.overrideWithValue('http://test/api'),
      collectionsRepositoryProvider.overrideWithValue(fake),
      if (!useRealCollectionsProvider)
        collectionsProvider.overrideWithValue(
          AsyncValue.data(collectionsOverride ?? _all),
        ),
      trashRepositoryProvider.overrideWithValue(trashFake),
    ],
  );
  addTearDown(container.dispose);
  final router = _TestRouter(collection: collection);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router.config(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return trashFake;
}

void main() {
  group('CollectionDetailScreen nesting', () {
    testWidgets('ряд детей-коллекций над сеткой', (tester) async {
      await pumpDetail(tester, collection: _all[0]);
      expect(find.text('Subcollections'), findsOneWidget);
      expect(find.text('Season 01'), findsOneWidget);
      expect(find.text('Season 02'), findsOneWidget);
    });

    testWidgets('у корня без детей ряда нет', (tester) async {
      await pumpDetail(tester, collection: _all[3]);
      expect(find.text('Subcollections'), findsNothing);
    });

    testWidgets('у вложенной — цепочка крошек на странице', (tester) async {
      // Кнопка «к родителю» стояла в AppBar, но для цепочки там места не
      // хватало — помещался обрывок первого слова. Теперь крошки на
      // странице: корень и текущая коллекция.
      await pumpDetail(tester, collection: _all[1]);

      expect(find.text('Сериал'), findsOneWidget);
      expect(find.text('Season 01'), findsOneWidget);
      // Кнопки в AppBar больше нет.
      expect(find.byIcon(Icons.upgrade_outlined), findsNothing);
    });

    testWidgets('у корня имя видно как заголовок цепочки', (tester) async {
      // Заголовка в AppBar нет (иначе имя дублировалось бы двумя
      // соседними строками) — значит, имя корня обязано быть в крошках,
      // иначе его не было бы видно вообще.
      await pumpDetail(tester, collection: _all[0]);

      expect(find.text('Сериал'), findsOneWidget);
      expect(find.byIcon(Icons.upgrade_outlined), findsNothing);
    });

    testWidgets('имя видно, пока список коллекций грузится', (tester) async {
      // Список нужен только для предков; пока он едет, имя текущей
      // коллекции должно быть видно сразу — заголовка в AppBar нет.
      //
      // settle: false — останавливаемся на первом кадре, пока провайдер
      // ещё в состоянии загрузки. С pumpAndSettle проверка прошла бы
      // вхолостую: данные уже приехали бы.
      await pumpDetail(
        tester,
        collection: _all[0],
        useRealCollectionsProvider: true,
        settle: false,
      );

      expect(find.text('Сериал'), findsOneWidget);
    });

    testWidgets('delete показывает счётчики из stats', (tester) async {
      final trashFake = await pumpDetail(tester, collection: _all[0]);
      trashFake.statsResult = const CollectionStats(
        subcollections: 2,
        items: 24,
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      // Фейк stats: 2 подколлекции, 24 файла.
      expect(
        find.text('Move "Сериал" to trash (2 subcollections, 24 files)?'),
        findsOneWidget,
      );
    });

    testWidgets('delete одиночной — старый текст без счётчика', (
      tester,
    ) async {
      await pumpDetail(tester, collection: _all[3]);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(
        find.text('Are you sure you want to delete "Фильмы"?'),
        findsOneWidget,
      );
    });

    testWidgets('перенос исключает себя и поддерево', (tester) async {
      await pumpDetail(tester, collection: _all[0]);
      await tester.tap(find.byIcon(Icons.drive_file_move_outlined));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      // В списке диалога — только «Фильмы»: себя и поддерево исключили.
      // (Заголовок AppBar «Сериал» под диалогом не считаем.)
      expect(
        find.descendant(of: dialog, matching: find.text('Сериал')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Season 01')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Фильмы')),
        findsOneWidget,
      );
    });
  });
}

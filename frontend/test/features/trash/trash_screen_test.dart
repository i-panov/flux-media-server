import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/trash/data/trash_remote_datasource.dart';
import 'package:flux_media_server/features/trash/presentation/providers/trash_providers.dart';
import 'package:flux_media_server/features/trash/presentation/screens/trash_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

import '../helpers/collection_helpers.dart';
import '../helpers/fake_repositories.dart';

Media _media(int id, String title) => Media(
  id: id,
  title: title,
  type: MediaType.video,
  fileSize: 1024,
);

/// Тестовый роутер с одной Trash-страницей (паттерн detail-теста).
class _TestRouter extends RootStackRouter {
  new() {
    TrashRoute.page = PageInfo(
      TrashRoute.name,
      builder: (data) => const TrashScreen(),
    );
  }

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: TrashRoute.page, initial: true),
  ];
}

Future<FakeTrashRepository> pumpTrash(
  WidgetTester tester, {
  TrashContents contents = const TrashContents(collections: [], media: []),
}) async {
  final fake = FakeTrashRepository()..contents = contents;
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [trashRepositoryProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  final router = _TestRouter();
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
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('TrashScreen', () {
    testWidgets('пустая корзина — заглушка', (tester) async {
      await pumpTrash(tester);
      expect(find.text('Trash is empty'), findsOneWidget);
    });

    testWidgets('элементы с кнопками вернуть/удалить', (tester) async {
      await pumpTrash(
        tester,
        contents: TrashContents(
          collections: [testCollection(1, 'Сериал')],
          media: [_media(7, 'Film')],
        ),
      );
      expect(find.text('Сериал'), findsOneWidget);
      expect(find.text('Film'), findsOneWidget);
      expect(find.byTooltip('Restore'), findsNWidgets(2));
      expect(find.byTooltip('Delete forever'), findsNWidgets(2));
    });

    testWidgets('restore коллекции зовёт репозиторий', (tester) async {
      final fake = await pumpTrash(
        tester,
        contents: TrashContents(
          collections: [testCollection(1, 'Сериал')],
          media: const [],
        ),
      );
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();
      expect(fake.restoreCollectionCalls, 1);
      expect(find.text('Restored'), findsOneWidget);
    });

    testWidgets('purge медиа спрашивает confirm', (tester) async {
      final fake = await pumpTrash(
        tester,
        contents: TrashContents(
          collections: const [],
          media: [_media(7, 'Film')],
        ),
      );
      await tester.tap(find.byTooltip('Delete forever'));
      await tester.pumpAndSettle();
      // Confirm упомянул стирание файла — отменяем.
      expect(find.textContaining('erased from disk'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.purgeMediaCalls, 0);
    });
  });
}

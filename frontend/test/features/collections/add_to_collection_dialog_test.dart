import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/fake_repositories.dart';

/// Открывает диалог «Добавить в коллекцию» для медиа [mediaId].
///
/// Регрессия: из коллекции было невозможно выйти — плитка уже добавленной
/// коллекции блокировала тап, а в аудио-разделе коллекции вообще не
/// показывались, то есть и места, где их видно, не было.
Future<void> pumpDialog(
  WidgetTester tester, {
  required int mediaId,
  required FakeCollectionsRepository repo,
  required List<Collection> collections,
  required List<Media> itemsInCollection,
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [collectionsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // Scaffold нужен ради ScaffoldMessenger: без него снекбар об
          // успехе/ошибке падает, и ошибка маскируется.
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showAddToCollectionDialog(
                context,
                mediaId,
                mediaType: 'audio',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('showAddToCollectionDialog', () {
    late FakeCollectionsRepository repo;

    setUp(() {
      // Стрелочные функции — отдельными переменными с явным типом: в
      // каскаде тело `() async => ...` проглатывает следующий `..`
      // (он попадает внутрь тела функции), а без контекста тип не
      // выводится.
      Future<Either<Failure, List<Collection>>> getCollections() async =>
          Right([collection(1, 'Плейлист')]);
      Future<Either<Failure, List<Media>>> getItemsFull(int _) async =>
          Right([media(7)]);
      Future<Either<Failure, void>> removeItem(int _, int _) async =>
          const Right(null);
      repo = FakeCollectionsRepository()
        ..onGetCollections = getCollections
        ..onGetItemsFull = getItemsFull
        ..onRemoveItem = removeItem;
    });

    testWidgets('уже добавленный элемент можно убрать из коллекции', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        mediaId: 7,
        repo: repo,
        collections: [collection(1, 'Плейлист')],
        itemsInCollection: [media(7)],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Плитка уже добавленной коллекции: кнопка удаления на месте.
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      expect(repo.removeItemCalls, [(1, 7)]);
    });

    testWidgets('не добавленный элемент не показывает кнопку удаления', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        mediaId: 8,
        repo: repo,
        collections: [collection(1, 'Плейлист')],
        itemsInCollection: [media(7)],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(repo.removeItemCalls, isEmpty);
    });
  });
}

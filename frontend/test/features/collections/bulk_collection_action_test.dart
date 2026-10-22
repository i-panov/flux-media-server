import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/domain/models/bulk_items_result.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/utils/bulk_collection_action.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/collection_helpers.dart';
import '../helpers/fake_repositories.dart';

void main() {
  group('addSelectionToCollection', () {
    late FakeCollectionsRepository repo;

    setUp(() {
      Future<Either<Failure, List<Collection>>> getCollections() async =>
          Right([testCollection(1, 'Плейлист', type: MediaType.audio)]);
      repo = FakeCollectionsRepository()..onGetCollections = getCollections;
    });

    testWidgets('выделенные файлы уходят в коллекцию одним запросом', (
      tester,
    ) async {
      // Групповая операция: сезон раскладывается по коллекции одним
      // запросом, а не по файлу.
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
              // Scaffold нужен ради ScaffoldMessenger: без него снекбар
              // об успехе падает, и ошибка маскируется.
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => addSelectionToCollection(
                    context,
                    ref,
                    mediaIds: const [1, 2, 3],
                    type: MediaType.audio,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Плейлист'));
      await tester.pumpAndSettle();

      // Запись содержит список, а списки сравниваются по идентичности —
      // поэтому поля проверяем по отдельности.
      expect(repo.addItemsBulkCalls, hasLength(1));
      expect(repo.addItemsBulkCalls.first.$1, 1);
      expect(repo.addItemsBulkCalls.first.$2, [1, 2, 3]);
    });

    testWidgets('отмена выбора ничего не отправляет', (tester) async {
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
            home: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => addSelectionToCollection(
                  context,
                  ref,
                  mediaIds: const [1, 2, 3],
                  type: MediaType.audio,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.addItemsBulkCalls, isEmpty);
    });
  });

  group('BulkItemsResult.parse', () {    test('разбирает списки ответа', () {
      final result = BulkItemsResult.parse({
        'added': [1, 2],
        'moved': [3],
        'removed': [4],
        'skipped': [5],
      });

      expect(result.added, [1, 2]);
      expect(result.moved, [3]);
      expect(result.removed, [4]);
      expect(result.skipped, [5]);
      expect(result.changedCount, 4);
    });

    test('битый ответ не роняет разбор', () {
      final result = BulkItemsResult.parse({'added': 'не список'});

      expect(result.added, isEmpty);
      expect(result.changedCount, 0);
    });
  });
}

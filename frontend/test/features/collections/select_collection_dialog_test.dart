import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/select_collection_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/collection_helpers.dart';
import '../helpers/fake_repositories.dart';

/// Открывает диалог выбора коллекции и складывает результат в [out].
Future<void> pumpDialog(
  WidgetTester tester, {
  required List<Collection?> out,
  required FakeCollectionsRepository repo,
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
        home: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () async {
              out.add(
                await showSelectCollectionDialog(
                  context,
                  ref,
                  type: MediaType.audio,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('showSelectCollectionDialog', () {
    late FakeCollectionsRepository repo;

    setUp(() {
      Future<Either<Failure, List<Collection>>> getCollections() async =>
          Right([testCollection(1, 'Плейлист', type: MediaType.audio)]);
      repo = FakeCollectionsRepository()..onGetCollections = getCollections;
    });

    testWidgets('коллекция выбирается и возвращается', (tester) async {
      final out = <Collection?>[];
      await pumpDialog(tester, out: out, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Плейлист'));
      await tester.pumpAndSettle();

      expect(out, hasLength(1));
      expect(out.single?.id, 1);
      expect(out.single?.name, 'Плейлист');
    });

    testWidgets('коллекция другого типа не показывается', (tester) async {
      Future<Either<Failure, List<Collection>>> getCollections() async =>
          Right([testCollection(1, 'Видео')]);
      repo = FakeCollectionsRepository()..onGetCollections = getCollections;
      final out = <Collection?>[];
      await pumpDialog(tester, out: out, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Видео'), findsNothing);
      expect(find.text('No collections'), findsOneWidget);
    });

    testWidgets('есть пункт создания коллекции', (tester) async {
      // Коллекции создавались только как побочка «добавить файл» —
      // выбрать коллекцию при загрузке было нечего.
      final out = <Collection?>[];
      await pumpDialog(tester, out: out, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('New Collection'), findsOneWidget);
    });
  });
}

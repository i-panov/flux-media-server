import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/screens/collection_detail_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

Media _media(int id, String title) => Media(
  id: id,
  title: title,
  type: MediaType.video,
  fileSize: 1,
);

Collection _collection() => Collection(
  id: 7,
  userId: 1,
  name: 'My videos',
  type: MediaType.video,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  SharedPreferences prefs,
  FakeCollectionsRepository repo,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        collectionsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CollectionDetailScreen(collection: _collection()),
      ),
    ),
  );
}

void main() {
  late SharedPreferences prefs;
  late FakeCollectionsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = FakeCollectionsRepository();
  });

  group('CollectionDetailScreen', () {
    testWidgets('показывает элементы коллекции', (tester) async {
      repo.onGetItemsFull = (_) async => Right([_media(1, 'One'), _media(2, 'Two')]);
      await _pumpScreen(tester, prefs, repo);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('пустая коллекция показывает заглушку', (tester) async {
      repo.onGetItemsFull = (_) async => const Right([]);
      await _pumpScreen(tester, prefs, repo);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('This collection is empty'), findsOneWidget);
    });

    testWidgets('удаление элемента подтверждает и убирает плитку', (
      tester,
    ) async {
      repo.onGetItemsFull = (_) async =>
          Right([_media(1, 'One'), _media(2, 'Two')]);
      // Два разных поля, каскад синтаксически невозможен.
      // ignore: cascade_invocations
      repo.onRemoveItem = (_, _) async => const Right(null);
      await _pumpScreen(tester, prefs, repo);
      await tester.pump(const Duration(milliseconds: 100));

      // Кнопка удаления на первой плитке.
      await tester.tap(find.byIcon(Icons.playlist_remove).first);
      await tester.pump(const Duration(milliseconds: 100));

      // Подтверждаем в диалоге.
      await tester.tap(find.text('Delete'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.removeItemCalls, [(7, 1)]);
      expect(find.text('One'), findsNothing);
      expect(find.text('Two'), findsOneWidget);
    });
  });
}

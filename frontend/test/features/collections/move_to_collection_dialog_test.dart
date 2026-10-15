import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/move_to_collection_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

import '../helpers/collection_helpers.dart';

/// Дом с кнопкой: открывает диалог по тапу, результат складывает в [out].
/// Как в реальном использовании — без showDialog прямо в build.
Future<void> pumpHome(
  WidgetTester tester, {
  required List<int?> out,
  Set<int> excludeIds = const {},
  bool allowRoot = false,
  AsyncValue<List<Collection>>? collections,
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      collectionsProvider.overrideWithValue(
        collections ??
            AsyncValue.data([
              testCollection(1, 'Сериал'),
              testCollection(2, 'Season 01', parentId: 1),
              testCollection(3, 'Музыка'),
            ]),
      ),
    ],
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
                await showMoveToCollectionDialog(
                  context,
                  ref,
                  type: MediaType.video,
                  excludeIds: excludeIds,
                  allowRoot: allowRoot,
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
  group('showMoveToCollectionDialog', () {
    testWidgets('цели видны, исключённые скрыты', (tester) async {
      final out = <int?>[];
      await pumpHome(tester, excludeIds: {1, 2}, out: out);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 1 и поддерево 2 исключены, 3 на месте.
      expect(find.text('Season 01'), findsNothing);
      expect(find.text('Музыка'), findsOneWidget);

      await tester.tap(find.text('Музыка'));
      await tester.pumpAndSettle();
      expect(out, [3]);
    });

    testWidgets('пункт «В корень» возвращает сентинел', (tester) async {
      final out = <int?>[];
      await pumpHome(tester, allowRoot: true, out: out);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('To root'));
      await tester.pumpAndSettle();
      expect(out, [moveToRootId]);
    });

    testWidgets('без allowRoot корневого пункта нет', (tester) async {
      final out = <int?>[];
      await pumpHome(tester, out: out);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('To root'), findsNothing);
      expect(find.text('Сериал'), findsOneWidget);
    });

    testWidgets('чужой тип скрыт', (tester) async {
      final out = <int?>[];
      await pumpHome(
        tester,
        out: out,
        collections: AsyncValue.data([
          testCollection(1, 'Сериал'),
          testCollection(9, 'Треки', type: MediaType.audio),
        ]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Диалог открыт для video: аудиоподборки нет, сезоны сериала
      // сюда не попадут — унесут только «Сериал».
      expect(find.text('Сериал'), findsOneWidget);
      expect(find.text('Треки'), findsNothing);
    });

    testWidgets('ошибка списка — retry виден', (tester) async {
      final out = <int?>[];
      await pumpHome(
        tester,
        out: out,
        collections: const AsyncValue.error('boom', StackTrace.empty),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      // Retry не закрывает диалог выбором: out пуст.
      expect(out, isEmpty);
    });
  });
}

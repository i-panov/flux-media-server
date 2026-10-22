import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_selection_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _video(int id) => Media(
  id: id,
  title: 'Video $id',
  type: MediaType.video,
  fileSize: 1,
);

void main() {
  group('mediaSelectionProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('переключение и сброс выделения', () {
      final notifier = container.read(mediaSelectionProvider('video').notifier)
        ..toggle(1);
      expect(container.read(mediaSelectionProvider('video')), {1});

      notifier.toggle(2);
      expect(container.read(mediaSelectionProvider('video')), {1, 2});

      // Повторное переключение снимает выделение.
      notifier.toggle(1);
      expect(container.read(mediaSelectionProvider('video')), {2});

      notifier.clear();
      expect(container.read(mediaSelectionProvider('video')), isEmpty);
    });

    test('области не путаются', () {
      // Выделение в библиотеке и внутри коллекции — разные вещи:
      // иначе «переместить» из коллекции относилось бы к чужому списку.
      container.read(mediaSelectionProvider('video').notifier).toggle(1);
      container
          .read(mediaSelectionProvider('collection:5').notifier)
          .toggle(2);

      expect(container.read(mediaSelectionProvider('video')), {1});
      expect(container.read(mediaSelectionProvider('collection:5')), {2});
    });
  });

  group('MediaCard', () {
    testWidgets('долгое нажатие выделяет карточку', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          baseUrlProvider.overrideWithValue('http://test/api'),
          sharedPreferencesProvider.overrideWithValue(prefs),
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
            home: Scaffold(
              body: MediaCard(media: _video(7)),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsNothing);

      await tester.longPress(find.byType(MediaCard));
      // Не pumpAndSettle: картинка грузится по сети и «осесть» не даёт.
      await tester.pump();

      expect(container.read(mediaSelectionProvider('video')), {7});
      // Отметка выделения видна — иначе непонятно, что попало в пачку.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

  });
}

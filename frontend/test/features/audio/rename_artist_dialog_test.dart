import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/rename_artist_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

Future<String?> _pumpDialog(WidgetTester tester, String currentName) {
  return showRenameArtistDialog(
    tester.element(find.byType(Scaffold)),
    currentName,
  );
}

Widget _host() {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SizedBox.shrink()),
  );
}

void main() {
  group('showRenameArtistDialog', () {
    testWidgets('возвращает обрезанное имя по Save', (tester) async {
      await tester.pumpWidget(_host());

      final future = _pumpDialog(tester, 'Old Name');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  New Name  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await future, 'New Name');
    });

    testWidgets('возвращает null по Cancel', (tester) async {
      await tester.pumpWidget(_host());

      final future = _pumpDialog(tester, 'Old Name');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await future, isNull);
    });

    testWidgets('поле предзаполнено текущим именем', (tester) async {
      await tester.pumpWidget(_host());

      unawaited(_pumpDialog(tester, 'Old Name'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Old Name');
    });
  });
}

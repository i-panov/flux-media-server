import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/widgets/source_link_row.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Мок канала url_launcher: фиксирует запуски и управляет результатом.
class _UrlLauncherMock {
  final List<String> launched = [];
  bool result = true;

  void install(TestWidgetsFlutterBinding binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'canLaunch') return true;
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
          return result;
        }
        return null;
      },
    );
  }

  void uninstall(TestWidgetsFlutterBinding binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  }
}

Widget _host(String url) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SourceLinkRow(url: url)),
  );
}

void main() {
  group('SourceLinkRow', () {
    testWidgets('показывает хост и открывает ссылку по тапу', (tester) async {
      final launcher = _UrlLauncherMock()..install(tester.binding);
      addTearDown(() => launcher.uninstall(tester.binding));

      await tester.pumpWidget(_host('https://www.youtube.com/watch?v=abc123'));

      // Хост вместо обрезанного полного URL.
      expect(find.text('www.youtube.com'), findsOneWidget);
      expect(find.textContaining('watch?v='), findsNothing);

      await tester.tap(find.text('www.youtube.com'));
      await tester.pump();

      expect(launcher.launched, ['https://www.youtube.com/watch?v=abc123']);
      // Снекбара об ошибке нет.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('неудачный запуск показывает снекбар', (tester) async {
      final launcher = _UrlLauncherMock()
        ..result = false
        ..install(tester.binding);
      addTearDown(() => launcher.uninstall(tester.binding));

      await tester.pumpWidget(_host('https://example.com/x'));

      await tester.tap(find.text('example.com'));
      await tester.pump();

      expect(launcher.launched, ['https://example.com/x']);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining("Couldn't open the link"), findsOneWidget);
    });

    testWidgets('невалидная ссылка не уходит наружу', (tester) async {
      final launcher = _UrlLauncherMock()..install(tester.binding);
      addTearDown(() => launcher.uninstall(tester.binding));

      // Легаси-кеш мог сохранить ссылку в обход валидации.
      await tester.pumpWidget(_host('javascript:alert(1)'));

      await tester.tap(find.text('javascript:alert(1)'));
      await tester.pump();

      expect(launcher.launched, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('строка доступна скринридеру', (tester) async {
      await tester.pumpWidget(_host('https://www.youtube.com/watch?v=abc123'));

      final semantics = tester.getSemantics(find.byType(SourceLinkRow));
      // Метка строки + слитый дочерний текст с хостом.
      expect(semantics.label, contains('Source link: www.youtube.com'));
      expect(semantics.flagsCollection.isButton, isTrue);
    });

    testWidgets('кнопка копирует ссылку в буфер', (tester) async {
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(_host('https://youtu.be/abc123'));

      await tester.tap(find.byTooltip('Copy link'));
      await tester.pump();

      expect(clipboard, 'https://youtu.be/abc123');
      expect(find.text('Link copied to clipboard'), findsOneWidget);
    });
  });
}

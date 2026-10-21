import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_overlay.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Обёртка с локализацией: кнопка play берёт подпись из AppLocalizations.
Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// Кадр 300x300 с постером, слоем жестов и опциональной кнопкой play.
Widget _frame({
  required VoidCallback onGesture,
  VoidCallback? onPlay,
}) {
  return _app(
    Center(
      child: SizedBox(
        width: 300,
        height: 300,
        child: VideoOverlay(
          poster: const ColoredBox(color: Colors.black),
          controls: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onGesture,
            child: const SizedBox.expand(),
          ),
          playButton: onPlay == null
              ? null
              : Center(child: PlayOverlayButton(onPressed: onPlay)),
        ),
      ),
    ),
  );
}

void main() {
  group('VideoOverlay', () {
    testWidgets('кнопка play поверх слоя жестов — тап достаётся ей', (
      tester,
    ) async {
      // Регрессия: слой жестов перехватывает тап по всей площади кадра
      // (HitTestBehavior.opaque). Если кнопка play окажется ПОД ним, она
      // выглядит живой, но не нажимается: тап уходит в переключение
      // видимости контролов. Порядок в VideoOverlay задаёт, кто сверху.
      var started = 0;
      var toggled = 0;

      await tester.pumpWidget(
        _frame(onGesture: () => toggled++, onPlay: () => started++),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(started, 1);
      // Слой жестов не должен был перехватить тап.
      expect(toggled, 0);
    });

    testWidgets('верхнего бара больше нет: выход из полного экрана — кнопкой в углу', (
      tester,
    ) async {
      // Стрелка «назад» в полноэкранном режиме висела поверх скрытых
      // контролов и занимала место, которое отведено кнопке полного
      // экрана в углу.
      await tester.pumpWidget(_frame(onGesture: () {}));

      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('тап по кадру мимо кнопки уходит в слой жестов', (
      tester,
    ) async {
      // Обратная сторона: кнопка занимает круг в центре, а кадр вокруг
      // неё должен оставаться кликабельным для слоя.
      var started = 0;
      var toggled = 0;

      await tester.pumpWidget(
        _frame(onGesture: () => toggled++, onPlay: () => started++),
      );

      // Угол кадра — заведомо вне круга кнопки в центре.
      final frame = tester.getRect(find.byType(VideoOverlay));
      await tester.tapAt(Offset(frame.left + 10, frame.top + 10));
      await tester.pump();

      expect(toggled, 1);
      expect(started, 0);
    });
  });

  group('PlayOverlayButton', () {
    testWidgets('нажимается и имеет семантическую метку', (tester) async {
      var started = 0;

      await tester.pumpWidget(
        _app(Center(child: PlayOverlayButton(onPressed: () => started++))),
      );

      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(started, 1);
    });
  });
}

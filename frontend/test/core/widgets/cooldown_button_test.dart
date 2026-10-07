import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/widgets/cooldown_button.dart';

void main() {
  group('CooldownController', () {
    test('изначально неактивен: кнопка доступна до первого старта', () {
      final cooldown = CooldownController(const Duration(seconds: 30));
      addTearDown(cooldown.dispose);

      expect(cooldown.isActive, isFalse);
      expect(cooldown.remaining, 0);
    });

    test('после start активен и тикает до нуля', () {
      FakeAsync().run((async) {
        final cooldown = CooldownController(const Duration(seconds: 3));
        addTearDown(cooldown.dispose);

        cooldown.start();
        expect(cooldown.isActive, isTrue);
        expect(cooldown.remaining, 3);

        async.elapse(const Duration(seconds: 1));
        expect(cooldown.isActive, isTrue);
        expect(cooldown.remaining, 2);

        async.elapse(const Duration(seconds: 2));
        expect(cooldown.isActive, isFalse);
        expect(cooldown.remaining, 0);
      });
    });

    test('повторный start перезапускает отсчёт', () {
      FakeAsync().run((async) {
        final cooldown = CooldownController(const Duration(seconds: 3));
        addTearDown(cooldown.dispose);

        cooldown.start();
        async.elapse(const Duration(seconds: 2));
        expect(cooldown.remaining, 1);

        cooldown.start();
        expect(cooldown.remaining, 3);
      });
    });

    test('после dispose таймер отменён: нотификаций больше нет', () {
      FakeAsync().run((async) {
        var notified = 0;
        final cooldown = CooldownController(const Duration(seconds: 3))
          ..addListener(() => notified++)
          ..start();
        final afterStart = notified;
        expect(afterStart, greaterThan(0));

        cooldown.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(notified, afterStart);
      });
    });
  });

  group('CooldownButton', () {
    testWidgets('изначально показывает подпись без счётчика', (tester) async {
      final cooldown = CooldownController(const Duration(seconds: 30));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CooldownButton(
              cooldown: cooldown,
              onPressed: () {},
              label: 'Get code',
            ),
          ),
        ),
      );

      expect(find.text('Get code'), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
      // Кнопка активна: onPressed не null.
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
      cooldown.dispose();
    });

    testWidgets('после старта показывает счётчик и блокируется', (
      tester,
    ) async {
      final cooldown = CooldownController(const Duration(seconds: 30));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CooldownButton(
              cooldown: cooldown,
              onPressed: () {},
              label: 'Get code',
            ),
          ),
        ),
      );

      cooldown.start();
      await tester.pump();

      expect(find.text('Get code (30s)'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      // Гасим 30-секундный таймер до конца теста: иначе binding падает
      // на pending timers при проверке инвариантов.
      cooldown.dispose();
    });
  });
}

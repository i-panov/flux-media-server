import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/widgets/search_sliver.dart';

/// `SearchPopScope`: системный back при активном поиске очищает поиск,
/// а не выходит из приложения.
void main() {
  testWidgets('canPop следует за текстом поля', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPopScope(
          controller: controller,
          onCleared: () => cleared++,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    PopScope popScope() =>
        tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));

    // Поле пустое — canPop=true, pop состоится (didPop=true),
    // очистка не вызывается.
    expect(popScope().canPop, isTrue);

    controller.text = 'matrix';
    await tester.pump();
    expect(popScope().canPop, isFalse);
    expect(cleared, 0);
  });

  testWidgets('системный back очищает поиск вместо выхода', (tester) async {
    final controller = TextEditingController(text: 'matrix');
    addTearDown(controller.dispose);

    PopScope popScope() =>
        tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));

    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPopScope(
          controller: controller,
          onCleared: () {
            cleared++;
            controller.clear();
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );

    // canPop=false: pop не происходит, вместо этого чистим поиск.
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(cleared, 1);
    expect(controller.text, isEmpty);
    // После очистки выход снова разрешён.
    expect(popScope().canPop, isTrue);
  });

  testWidgets('состоявшийся pop не трогает поиск', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPopScope(
          controller: controller,
          onCleared: () => cleared++,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    PopScope popScope() =>
        tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));

    // Поле пустое — canPop=true, pop состоится (didPop=true),
    // очистка не вызывается.
    expect(popScope().canPop, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(cleared, 0);
  });
}

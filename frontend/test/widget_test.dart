import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FluxApp(
      router: null,
      hasServerUrl: false,
    ));
    expect(find.text('Flux Media Server'), findsWidgets);
  });
}

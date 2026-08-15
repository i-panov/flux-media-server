import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/main_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Тестовый роутер: страницы MainScreen/Videos/Audio — заглушки,
/// чтобы не тянуть в тест features.
class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
          page: MainRoute.page,
          initial: true,
          children: [
            AutoRoute(page: VideoRoute.page, initial: true),
            AutoRoute(page: AudioRoute.page),
          ],
        ),
      ];

  @override
  final Map<String, PageFactory> pagesMap = {
    MainRoute.name: (data) => AutoRoutePage(
          routeData: data,
          child: MainScreen(
            tabs: const [VideoRoute(), AudioRoute()],
            settingsRoute: const SettingsRoute(),
            miniPlayer: const SizedBox.shrink(),
            isOffline: false,
            onRetry: () {},
          ),
        ),
    VideoRoute.name: (data) =>
        AutoRoutePage(routeData: data, child: const SizedBox()),
    AudioRoute.name: (data) =>
        AutoRoutePage(routeData: data, child: const SizedBox()),
  };
}

void main() {
  Future<void> pumpMain(WidgetTester tester) async {
    final router = _TestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on mobile the back gesture is blocked to exit the app',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpMain(tester);

    final popScope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScope.canPop, isFalse);
    expect(popScope.onPopInvokedWithResult, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on desktop/web the back navigation is not blocked',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpMain(tester);

    final popScope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScope.canPop, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}

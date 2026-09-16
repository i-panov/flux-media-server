import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/main_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Тестовый роутер: страницы MainScreen/Videos/Audio — заглушки,
/// чтобы не тянуть в тест features.
///
/// В auto_route 9+ страницы строятся из статических `PageInfo` у
/// Route-классов (pagesMap больше не используется), поэтому для
/// изоляции теста подменяем PageInfo тестовыми заглушками.
class _TestRouter extends RootStackRouter {
  new() {
    MainRoute.page = PageInfo(
      MainRoute.name,
      builder: (data) => MainScreen(
        tabs: const [VideoRoute(), AudioRoute()],
        settingsRoute: const SettingsRoute(),
        miniPlayer: const SizedBox.shrink(),
        isOffline: false,
        onRetry: () {},
      ),
    );
    VideoRoute.page = PageInfo(
      VideoRoute.name,
      builder: (data) => const SizedBox(),
    );
    AudioRoute.page = PageInfo(
      AudioRoute.name,
      builder: (data) => const SizedBox(),
    );
  }

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

  testWidgets('on mobile the back gesture is blocked to exit the app', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpMain(tester);

    final popScope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScope.canPop, isFalse);
    expect(popScope.onPopInvokedWithResult, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on desktop/web the back navigation is not blocked', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpMain(tester);

    final popScope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScope.canPop, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/router/auth_guard.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final serverUrl = prefs.getString('server_url');

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  if (serverUrl != null) {
    await container.read(settingsProvider.notifier).init();
    final settings = container.read(settingsProvider).settings;
    if (settings.authToken != null) {
      // Non-blocking: splash screen handles loading state
      unawaited(container.read(authProvider.notifier).checkAuthStatus());
    }
  }

  final router = AppRouter(authGuard: AuthGuard(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: FluxApp(router: router, hasServerUrl: serverUrl != null),
    ),
  );
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l?.checkingAuthentication ?? 'Checking authentication...'),
          ],
        ),
      ),
    );
  }
}

class FluxApp extends ConsumerStatefulWidget {
  const FluxApp({required this.router, required this.hasServerUrl, super.key});

  final AppRouter router;
  final bool hasServerUrl;

  @override
  ConsumerState<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends ConsumerState<FluxApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState is AuthAuthenticated) {
        widget.router.replaceAll([const MainRoute()]);
      } else if (authState is! AuthLoading && widget.hasServerUrl) {
        widget.router.replace(const LoginRoute());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(settingsProvider.select((s) => s.settings.locale));
    final authState = ref.watch(authProvider);

    ref.listen(authProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.router.replaceAll([const MainRoute()]);
        });
      } else if (next is AuthInitial && widget.hasServerUrl) {
        if (previous is AuthAuthenticated || previous is AuthLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.router.replace(const LoginRoute());
          });
        }
      } else if (next is AuthError && widget.hasServerUrl && previous is AuthLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.router.replace(const LoginRoute());
        });
      }
    });

    final showSplash = authState is AuthLoading ||
        (authState is AuthInitial &&
            widget.hasServerUrl &&
            ref.read(settingsProvider).settings.authToken != null);

    return MaterialApp.router(
      title: 'Flux Media Server',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: widget.router.config(),
      builder: showSplash
          ? (context, child) => const SplashScreen()
          : null,
    );
  }
}

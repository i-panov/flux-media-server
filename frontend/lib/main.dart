import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/router/auth_guard.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

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

  final router = AppRouter(authGuard: AuthGuard(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: FluxApp(router: router, hasServerUrl: serverUrl != null),
    ),
  );
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
    if (widget.hasServerUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.router.replace(const LoginRoute());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous is AuthAuthenticated && next is AuthInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.router.replace(const LoginRoute());
        });
      }
    });

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
      themeMode: ThemeMode.system,
      routerConfig: widget.router.config(),
    );
  }
}

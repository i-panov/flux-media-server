import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';

/// Protects routes that require authentication.
class AuthGuard extends AutoRouteGuard {
  AuthGuard(this._container);

  final ProviderContainer _container;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final authState = _container.read(authProvider);
    if (authState is AuthAuthenticated) {
      resolver.next();
    } else {
      router.replace(const LoginRoute());
    }
  }
}

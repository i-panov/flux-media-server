import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref);
});

final tokenRefreshInterceptorProvider = Provider<TokenRefreshInterceptor>((ref) {
  return TokenRefreshInterceptor(ref);
});

/// Provides the base URL derived from settings.
/// Only changes when serverUrl actually changes.
final baseUrlProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  final raw = settings.settings.serverUrl ?? 'http://localhost:8080';
  final uri = Uri.parse(raw);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty || segments.last != 'api') {
    segments.add('api');
  }
  return uri.replace(pathSegments: segments).toString();
});

/// Provides the API client. Only recreates when baseUrl changes,
/// not on every settings state change (e.g. token refresh).
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authInterceptor = ref.watch(authInterceptorProvider);
  final tokenRefreshInterceptor = ref.watch(tokenRefreshInterceptorProvider);
  return ApiClient.create(
    baseUrl: baseUrl,
    authInterceptor: authInterceptor,
    tokenRefreshInterceptor: tokenRefreshInterceptor,
  );
});

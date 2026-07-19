import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref);
});

/// Provides the base URL derived from settings.
/// Only changes when serverUrl actually changes.
final baseUrlProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  var baseUrl = settings.settings.serverUrl ?? 'http://localhost:8080';
  if (!baseUrl.endsWith('/api')) {
    baseUrl = '$baseUrl/api';
  }
  return baseUrl;
});

/// Provides the API client. Only recreates when baseUrl changes,
/// not on every settings state change (e.g. token refresh).
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authInterceptor = ref.watch(authInterceptorProvider);
  return ApiClient.create(baseUrl: baseUrl, authInterceptor: authInterceptor);
});

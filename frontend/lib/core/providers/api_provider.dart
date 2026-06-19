import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  var baseUrl = settings.settings.serverUrl ?? 'http://localhost:8080';
  if (!baseUrl.endsWith('/api')) {
    baseUrl = '$baseUrl/api';
  }
  final authInterceptor = ref.watch(authInterceptorProvider);
  return ApiClient.create(baseUrl: baseUrl, authInterceptor: authInterceptor);
});

final baseUrlProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  var baseUrl = settings.settings.serverUrl ?? 'http://localhost:8080';
  if (!baseUrl.endsWith('/api')) {
    baseUrl = '$baseUrl/api';
  }
  return baseUrl;
});

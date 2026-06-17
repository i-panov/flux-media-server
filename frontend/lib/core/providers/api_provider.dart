import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  final baseUrl = settings.settings.serverUrl ?? 'http://localhost:8080/api';
  final authInterceptor = ref.watch(authInterceptorProvider);
  return ApiClient.create(baseUrl: baseUrl, authInterceptor: authInterceptor);
});

final baseUrlProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.settings.serverUrl ?? 'http://localhost:8080/api';
});

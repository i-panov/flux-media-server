import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';

/// True, когда последняя проверка сервера завершилась сетевой ошибкой
/// ([AuthState.error] с isOffline). Офлайн-режим показывает только
/// скачанный контент и баннер с повторной проверкой.
final isOfflineProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is AuthError) {
    return authState.isOffline;
  }
  return false;
});

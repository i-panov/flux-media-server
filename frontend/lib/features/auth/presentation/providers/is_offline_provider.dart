import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';

/// Фиксирует сетевую недоступность по факту любого запроса приложения.
///
/// Проверка сессии ([AuthNotifier.checkAuthStatus]) выполняется при старте
/// и по Retry — если интернет пропал уже ПОСЛЕ запуска, списки падают с
/// сетевыми ошибками, но auth-состояние об этом не знает. Этот провайдер
/// помечается каждым сетевым сбоем и сбрасывается при успешном запросе.
class NetworkStatusNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Сеть недоступна (сетевая ошибка какого-либо запроса).
  void markOffline() => state = true;

  /// Сеть снова доступна (успешный запрос).
  void markOnline() => state = false;
}

final networkStatusProvider =
    NotifierProvider<NetworkStatusNotifier, bool>(NetworkStatusNotifier.new);

/// True, когда приложение работает в офлайн-режиме: либо последняя
/// проверка сервера завершилась сетевой ошибкой ([AuthState.error] с
/// isOffline), либо какой-то запрос приложения упал из-за отсутствия
/// сети ([networkStatusProvider]). Офлайн-режим показывает только
/// скачанный контент и баннер с повторной проверкой.
final isOfflineProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is AuthError) {
    return authState.isOffline;
  }
  return ref.watch(networkStatusProvider);
});

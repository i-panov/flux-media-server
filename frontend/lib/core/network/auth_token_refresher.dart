import 'dart:async';

/// Единая точка обновления токенов для всего приложения.
///
/// Гарантирует, что параллельные запросы, получившие 401, ждут один
/// общий refresh вместо конкурентных POST /auth/refresh (иначе
/// выживает только последний ответ, а предыдущие токены становятся
/// невалидными).
///
/// Не зависит от features: логика refresh-запроса и реакция на неудачу
/// передаются колбэками, поэтому core/network не знает про auth.
class AuthTokenRefresher {
  AuthTokenRefresher({
    required Future<({String token, String refreshToken})?> Function(
      String refreshToken,
    ) performRefresh,
    required Future<void> Function() onRefreshFailure,
  })  : _performRefresh = performRefresh,
        _onRefreshFailure = onRefreshFailure;

  /// Выполняет refresh-запрос и сохраняет новые токены.
  /// Возвращает `null`, если сервер отклонил refresh-токен.
  final Future<({String token, String refreshToken})?> Function(
    String refreshToken,
  ) _performRefresh;

  /// Вызывается при неудачном refresh (очистка токенов и logout).
  final Future<void> Function() _onRefreshFailure;

  /// Токены, полученные последним успешным refresh.
  ({String token, String refreshToken})? _lastTokens;

  Future<bool>? _inFlight;

  /// Токены последнего успешного refresh (null, если refresh ещё не
  /// выполнялся или завершился неудачей).
  ({String token, String refreshToken})? get lastTokens => _lastTokens;

  /// Запускает refresh (или ожидает уже идущий) и возвращает успех.
  ///
  /// [refreshToken] == null означает «нечего обновлять» — сразу false.
  Future<bool> refresh(String? refreshToken) {
    if (refreshToken == null || refreshToken.isEmpty) {
      return Future<bool>.value(false);
    }
    return _inFlight ??= _doRefresh(refreshToken)
        .whenComplete(() => _inFlight = null);
  }

  Future<bool> _doRefresh(String refreshToken) async {
    _lastTokens = null;
    try {
      final tokens = await _performRefresh(refreshToken)
          .timeout(const Duration(seconds: 10));
      if (tokens != null) {
        _lastTokens = tokens;
        return true;
      }
    } on Exception {
      // Сетевая ошибка или таймаут — считаем refresh неудачным.
    }
    await _onRefreshFailure();
    return false;
  }
}

import 'dart:async';

import 'package:flux_media_server/core/utils/logger.dart';

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

  Future<({String token, String refreshToken})?>? _inFlight;

  /// Запускает refresh (или ожидает уже идущий) и возвращает успех.
  ///
  /// [refreshToken] == null означает «нечего обновлять» — это тоже
  /// неудача: вызывается колбэк onRefreshFailure, возвращается false.
  Future<bool> refresh(String? refreshToken) async {
    final tokens = await refreshTokens(refreshToken);
    return tokens != null;
  }

  /// Запускает refresh (или ожидает уже идущий) и возвращает новые
  /// токены напрямую; `null` — обновить не удалось (нет токена,
  /// отказ сервера, сетевая ошибка). При неудаче вызывается колбэк
  /// onRefreshFailure. Токены возвращаются из результата, а не из
  /// побочного поля, поэтому провал параллельного чужого refresh
  /// не может «обнулить» результат успешного.
  Future<({String token, String refreshToken})?> refreshTokens(
    String? refreshToken,
  ) {
    if (refreshToken == null || refreshToken.isEmpty) {
      return _onRefreshFailure().then((_) => null);
    }
    return _inFlight ??=
        _doRefresh(refreshToken).whenComplete(() => _inFlight = null);
  }

  Future<({String token, String refreshToken})?> _doRefresh(
    String refreshToken,
  ) async {
    try {
      final tokens = await _performRefresh(refreshToken)
          .timeout(const Duration(seconds: 10));
      if (tokens != null) return tokens;
    } on Exception catch (e) {
      AppLogger.error('Token refresh failed', e);
    }
    await _onRefreshFailure();
    return null;
  }
}

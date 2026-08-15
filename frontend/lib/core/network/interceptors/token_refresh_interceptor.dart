import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';

/// Signal that a token refresh succeeded and the request should be retried.
class TokenRefreshedException implements Exception {
  const TokenRefreshedException();
}

/// Intercepts 401 responses, attempts token refresh, and signals retry.
///
/// Использует единый [AuthTokenRefresher]: параллельные 401-запросы
/// ждут один общий refresh вместо конкурентных запросов.
class TokenRefreshInterceptor implements ResponseInterceptor {
  TokenRefreshInterceptor(this._ref);

  final Ref _ref;

  @override
  FutureOr<Response<dynamic>> onResponse(Response<dynamic> response) async {
    if (response.statusCode != 401) return response;

    // 401 на auth-эндпоинтах — бизнес-ошибка, а не истёкшая сессия:
    // неверный код/токен не должны триггерить refresh.
    final path = response.base.request?.url.path ?? '';
    if (path.contains('/auth/refresh') ||
        path.contains('/auth/request-code') ||
        path.contains('/auth/verify-code')) {
      return response;
    }

    final refreshToken = _ref.read(settingsProvider).settings.refreshToken;
    final refresher = _ref.read(authTokenRefresherProvider);
    final tokens = await refresher.refreshTokens(refreshToken);

    if (tokens != null) {
      throw const TokenRefreshedException();
    }

    // Refresh не удался — сессия мертва: сбрасываем auth, иначе
    // приложение остаётся «залогиненным» со стейлым user и пустыми
    // токенами (каждый запрос — 401 без редиректа).
    AppLogger.error('Token refresh failed — session expired');
    _ref.read(authProvider.notifier).expireSession();
    return response;
  }
}

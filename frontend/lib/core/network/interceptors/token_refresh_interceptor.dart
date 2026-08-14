import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';

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

    // Запросы на /auth/refresh не должны рекурсивно вызывать refresh.
    final path = response.base.request?.url.path ?? '';
    if (path.contains('/auth/refresh')) return response;

    final refreshToken = _ref.read(settingsProvider).settings.refreshToken;
    final refresher = _ref.read(authTokenRefresherProvider);
    final refreshSucceeded = await refresher.refresh(refreshToken);

    if (refreshSucceeded) {
      throw const TokenRefreshedException();
    }

    // Refresh failed — tokens were cleared. Return 401 to force re-login.
    return response;
  }
}

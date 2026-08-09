import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:http/http.dart' as http;

/// Signal that a token refresh succeeded and the request should be retried.
class TokenRefreshedException implements Exception {
  const TokenRefreshedException();
}

/// Intercepts 401 responses, attempts token refresh, and signals retry.
///
/// Uses a [Future] instead of a binary flag so that parallel 401-requests
/// wait for the single ongoing refresh and then retry with the new token
/// instead of silently failing.
// ignore: must_be_immutable
class TokenRefreshInterceptor implements ResponseInterceptor {
  TokenRefreshInterceptor(this._ref);

  final Ref _ref;
  Future<bool>? _refreshFuture;

  Future<bool> _doRefresh() async {
    final refreshToken = _ref.read(settingsProvider).settings.refreshToken;
    if (refreshToken == null) return false;

    final baseUrl = _ref.read(baseUrlProvider);
    final uri = Uri.parse('$baseUrl/auth/refresh');
    final httpResponse = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    ).timeout(const Duration(seconds: 10));

    if (httpResponse.statusCode == 200) {
      final data = jsonDecode(httpResponse.body) as Map<String, dynamic>;
      final newAccessToken = data['token'] as String;
      final newRefreshToken = data['refresh_token'] as String;
      await _ref
          .read(settingsProvider.notifier)
          .setTokens(newAccessToken, newRefreshToken);
      return true;
    }

    // Refresh failed (401, 403, 500, etc.) — clear all tokens so the
    // user is forced to log in again. This prevents stale tokens from
    // causing infinite 401 loops.
    await _ref.read(settingsProvider.notifier).logout();
    return false;
  }

  @override
  FutureOr<Response<dynamic>> onResponse(Response<dynamic> response) async {
    if (response.statusCode != 401) return response;

    // Ensure only one refresh runs at a time; other 401 responses
    // wait for the single ongoing refresh.
    final refreshSucceeded = await (_refreshFuture ??= _doRefresh()
        .whenComplete(() => _refreshFuture = null));

    if (refreshSucceeded) {
      throw const TokenRefreshedException();
    }

    // Refresh failed — tokens were cleared. Return 401 to force re-login.
    return response;
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

/// Signal that a token refresh succeeded and the request should be retried.
class TokenRefreshedException implements Exception {
  const TokenRefreshedException();
}

/// Intercepts 401 responses, attempts token refresh, and signals retry.
class TokenRefreshInterceptor implements ResponseInterceptor {
  TokenRefreshInterceptor(this._ref);

  final Ref _ref;

  @override
  FutureOr<Response<dynamic>> onResponse(Response<dynamic> response) async {
    if (response.statusCode != 401) return response;

    final refreshToken = _ref.read(settingsProvider).settings.refreshToken;
    if (refreshToken == null) return response;

    try {
      final baseUrl = _ref.read(baseUrlProvider);
      final uri = Uri.parse('$baseUrl/auth/refresh');
      final httpResponse = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (httpResponse.statusCode == 200) {
        final data = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        final newAccessToken = data['token'] as String;
        final newRefreshToken = data['refresh_token'] as String;
        await _ref
            .read(settingsProvider.notifier)
            .setTokens(newAccessToken, newRefreshToken);
        throw const TokenRefreshedException();
      }
    } catch (e) {
      if (e is TokenRefreshedException) rethrow;
      // Refresh failed — fall through to normal 401 handling
    }

    return response;
  }
}

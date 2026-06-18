import 'dart:async';

import 'package:chopper/chopper.dart';

/// Adds Bearer token to outgoing requests.
// ignore: must_be_immutable
class AuthInterceptor implements RequestInterceptor {
  String? _token;

  /// Sets the authentication token.
  void setToken(String token) => _token = token;

  /// Clears the authentication token.
  void clearToken() => _token = null;

  /// Current token value.
  String? get token => _token;

  @override
  FutureOr<Request> onRequest(Request request) {
    if (_token == null) return request;
    return request.copyWith(
      headers: {
        ...request.headers,
        'Authorization': 'Bearer $_token',
      },
    );
  }
}

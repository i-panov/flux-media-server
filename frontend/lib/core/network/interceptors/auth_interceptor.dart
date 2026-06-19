import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

/// Adds Bearer token to outgoing requests by reading it from Riverpod state.
class AuthInterceptor implements RequestInterceptor {
  AuthInterceptor(this._ref);

  final Ref _ref;

  @override
  FutureOr<Request> onRequest(Request request) {
    final settings = _ref.read(settingsProvider).settings;
    final token = settings.authToken;
    if (token == null) return request;
    return request.copyWith(
      headers: {
        ...request.headers,
        'Authorization': 'Bearer $token',
      },
    );
  }
}

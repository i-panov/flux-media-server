import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';

/// Adds Bearer token to outgoing requests by reading it from Riverpod state.
class AuthInterceptor implements Interceptor {
  new(this._ref);

  final Ref _ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) {
    final settings = _ref.read(settingsProvider).settings;
    final token = settings.authToken;
    if (token == null) return chain.proceed(chain.request);
    return chain.proceed(
      chain.request.copyWith(
        headers: {...chain.request.headers, 'Authorization': 'Bearer $token'},
      ),
    );
  }
}

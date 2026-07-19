import 'dart:async';
import 'dart:developer' as developer;

import 'package:chopper/chopper.dart';

/// Logs HTTP requests and responses, masking the Authorization header.
class SafeLoggingInterceptor implements RequestInterceptor, ResponseInterceptor {
  @override
  FutureOr<Request> onRequest(Request request) {
    final safeHeaders = Map<String, String>.from(request.headers);
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = 'Bearer ***';
    }
    developer.log('--> ${request.method} ${request.url}');
    developer.log('Headers: $safeHeaders');
    return request;
  }

  @override
  FutureOr<Response> onResponse(Response response) {
    developer.log('<-- ${response.statusCode} ${response.base.request?.url}');
    return response;
  }
}

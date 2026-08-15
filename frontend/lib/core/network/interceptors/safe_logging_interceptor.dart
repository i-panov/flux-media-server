import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/utils/logger.dart';

/// Logs HTTP requests and responses, masking the Authorization header.
class SafeLoggingInterceptor
    implements RequestInterceptor, ResponseInterceptor {
  @override
  FutureOr<Request> onRequest(Request request) {
    final safeHeaders = Map<String, String>.from(request.headers);
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = 'Bearer ***';
    }
    AppLogger.info('--> ${request.method} ${request.url}');
    AppLogger.info('Headers: $safeHeaders');
    return request;
  }

  @override
  FutureOr<Response<dynamic>> onResponse(Response<dynamic> response) {
    AppLogger.info('<-- ${response.statusCode} ${response.base.request?.url}');
    return response;
  }
}

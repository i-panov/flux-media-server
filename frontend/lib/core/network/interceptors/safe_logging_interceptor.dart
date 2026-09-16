import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/utils/logger.dart';

/// Logs HTTP requests and responses, masking the Authorization header.
class SafeLoggingInterceptor implements Interceptor {
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    final request = chain.request;
    final safeHeaders = Map<String, String>.from(request.headers);
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = 'Bearer ***';
    }
    AppLogger.info('--> ${request.method} ${request.url}');
    AppLogger.info('Headers: $safeHeaders');

    final response = await chain.proceed(request);

    AppLogger.info('<-- ${response.statusCode} ${response.base.request?.url}');
    return response;
  }
}

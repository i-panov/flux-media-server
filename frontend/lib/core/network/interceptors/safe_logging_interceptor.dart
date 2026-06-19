import 'dart:async';

import 'package:chopper/chopper.dart';

/// Logs HTTP requests and responses, masking the Authorization header.
class SafeLoggingInterceptor implements Interceptor {
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final request = chain.request;
    final safeHeaders = Map<String, String>.from(request.headers);
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = 'Bearer ***';
    }
    // ignore: avoid_print
    print('--> ${request.method} ${request.url}');
    // ignore: avoid_print
    print('Headers: $safeHeaders');

    final response = await chain.proceed(request);

    // ignore: avoid_print
    print('<-- ${response.statusCode} ${request.url}');
    return response;
  }
}

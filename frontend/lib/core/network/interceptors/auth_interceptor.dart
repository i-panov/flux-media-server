import 'package:chopper/chopper.dart';

class AuthInterceptor implements Interceptor {
  String? _token;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  String? get token => _token;

  @override
  Future<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    final request = _addToken(chain.request);
    return chain.proceed(request);
  }

  Request _addToken(Request request) {
    if (_token == null) return request;
    return request.copyWith(
      headers: {
        ...request.headers,
        'Authorization': 'Bearer $_token',
      },
    );
  }
}

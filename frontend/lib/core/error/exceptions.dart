class ServerException implements Exception {
  const ServerException({required this.message});

  final String message;
}

class CacheException implements Exception {
  const CacheException({required this.message});

  final String message;
}

class AuthException implements Exception {
  const AuthException({required this.message});

  final String message;
}

class NetworkException implements Exception {
  const NetworkException({required this.message});

  final String message;
}

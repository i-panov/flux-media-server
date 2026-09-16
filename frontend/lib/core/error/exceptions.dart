class ServerException implements Exception {
  const new({required this.message});

  final String message;
}

class CacheException implements Exception {
  const new({required this.message});

  final String message;
}

class AuthException implements Exception {
  const new({required this.message});

  final String message;
}

class NetworkException implements Exception {
  const new({required this.message});

  final String message;
}

/// Сигнал отмены загрузки (upload/download) пользователем.
class UploadCancelledException implements Exception {
  const new();
}

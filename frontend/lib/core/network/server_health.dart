import 'dart:io';

/// Ошибка health-check сервера: сервер ответил, но не 200 OK.
class ServerHealthException implements Exception {
  const new(this.statusCode);

  final int statusCode;
}

/// Проверяет доступность сервера по его `/api/health`.
///
/// Вынесено из `ServerSetupScreen`, чтобы ветки «не-200» и «недоступен»
/// покрывались тестами через локальный `HttpServer`, а не моками
/// `HttpClient`. Флаг доверия применяется так же, как в экране: только
/// при явном согласии пользователя.
Future<void> checkServerHealth(
  Uri healthUri, {
  required bool trustSelfSigned,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = trustSelfSigned
        ? (cert, host, port) => true
        : null;
  try {
    final request = await client.getUrl(healthUri);
    final response = await request.close();
    // Прочитать тело ответа, чтобы освободить соединение.
    await response.drain<void>();

    if (response.statusCode != HttpStatus.ok) {
      throw ServerHealthException(response.statusCode);
    }
  } finally {
    // Закрываем клиент в любом случае, чтобы не было утечки сокетов.
    client.close(force: true);
  }
}

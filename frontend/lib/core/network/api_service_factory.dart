import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

/// HTTP-клиент с таймаутами, общий для всех Chopper-сервисов.
///
/// Обычные запросы получают таймаут 30 секунд, multipart-загрузки —
/// 120 секунд (файлы могут быть большими). Базовый [HttpClient]
/// дополнительно имеет connectionTimeout 10 секунд.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient()
      : _inner = IOClient(
          HttpClient()..connectionTimeout = const Duration(seconds: 10),
        );

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final timeout = request is http.MultipartRequest
        ? const Duration(seconds: 120)
        : const Duration(seconds: 30);
    return _inner.send(request).timeout(timeout);
  }

  /// Закрывает внутренний HttpClient и освобождает сокеты.
  @override
  void close() {
    _inner.close();
  }
}

/// Результат создания Chopper-клиента.
///
/// httpClient нужно закрыть через `ref.onDispose`, когда клиент
/// становится не нужен (например, при смене baseUrl).
typedef CreatedChopperClient = ({
  ChopperClient client,
  TimeoutHttpClient httpClient,
});

/// Общая инфраструктура создания Chopper-клиентов: базовый
/// [ChopperClient] с [JsonConverter] и переданными интерцепторами.
CreatedChopperClient createChopperClient({
  required String baseUrl,
  required List<ChopperService> services,
  Iterable<dynamic>? interceptors,
}) {
  final httpClient = TimeoutHttpClient();
  final client = ChopperClient(
    baseUrl: Uri.parse(baseUrl),
    services: services,
    client: httpClient,
    converter: const JsonConverter(),
    interceptors: interceptors ?? const [],
  );
  return (client: client, httpClient: httpClient);
}

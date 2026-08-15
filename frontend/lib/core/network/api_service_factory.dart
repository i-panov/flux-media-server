import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

/// HTTP-клиент с таймаутами, общий для всех Chopper-сервисов.
///
/// Обычные запросы получают таймаут 30 секунд, multipart-загрузки —
/// 120 секунд (файлы могут быть большими). Базовый [HttpClient]
/// дополнительно имеет connectionTimeout 10 секунд.
///
/// На таймауте базовый запрос отменяется через [http.Abortable],
/// а не просто «бросается» [TimeoutException]: иначе соединение
/// продолжало бы жить в фоне до конца ответа.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient({
    this.requestTimeout = const Duration(seconds: 30),
    this.uploadTimeout = const Duration(seconds: 120),
  }) : _inner = IOClient(
          HttpClient()..connectionTimeout = const Duration(seconds: 10),
        );

  final http.Client _inner;

  /// Таймаут для обычных запросов.
  final Duration requestTimeout;

  /// Таймаут для multipart-загрузок.
  final Duration uploadTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final timeout =
        request is http.MultipartRequest ? uploadTimeout : requestTimeout;
    final completer = Completer<void>();
    final abortable = _withAbortTrigger(request, completer.future);
    return _inner.send(abortable).timeout(
          timeout,
          onTimeout: () {
            // Завершаем триггер отмены: соединение закрывается.
            if (!completer.isCompleted) completer.complete();
            throw TimeoutException('Request timed out');
          },
        );
  }

  /// Копирует [request] в abortable-версию (http 1.6+), привязанную
  /// к [trigger]. Неизвестные типы запросов возвращаются без изменений.
  static http.BaseRequest _withAbortTrigger(
    http.BaseRequest request,
    Future<void> trigger,
  ) {
    if (request is http.MultipartRequest) {
      return http.AbortableMultipartRequest(
        request.method,
        request.url,
        abortTrigger: trigger,
      )
        ..headers.addAll(request.headers)
        ..fields.addAll(request.fields)
        ..files.addAll(request.files)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
    }
    if (request is http.Request) {
      return http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: trigger,
      )
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..encoding = request.encoding
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
    }
    return request;
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

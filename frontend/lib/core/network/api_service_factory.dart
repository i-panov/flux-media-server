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
  new({
    this.requestTimeout = const Duration(seconds: 30),
    this.uploadTimeout = const Duration(seconds: 120),
    this.trustSelfSignedCertificates = false,
    HttpClient Function()? httpClientFactory,
  }) : _inner = IOClient(
         _createBaseClient(httpClientFactory)
           ..connectionTimeout = const Duration(seconds: 10)
           // Флаг доверия из настроек применяется ЗДЕСЬ, а не только на
           // health-check в ServerSetupScreen: иначе проверка проходила бы,
           // а все реальные запросы падали бы с ошибкой сертификата.
           ..badCertificateCallback = trustSelfSignedCertificates
               ? (cert, host, port) => true
               : null,
       );

  /// Фабрика базового клиента: точка расширения для тестов, чтобы
  /// подсмотреть выставленный `badCertificateCallback` на настоящем
  /// `HttpClient`. В проде всегда дефолтный конструктор.
  static HttpClient _createBaseClient(HttpClient Function()? factory) =>
      factory != null ? factory() : HttpClient();

  final http.Client _inner;

  /// Таймаут для обычных запросов.
  final Duration requestTimeout;

  /// Таймаут для multipart-загрузок.
  final Duration uploadTimeout;

  /// Принимать самоподписанные сертификаты (небезопасный HTTPS).
  ///
  /// ВАЖНО: покрывает только трафик Dart-http. Потоки видео/аудио идёт
  /// через mpv (media_kit), у которого нет настраиваемого TLS-колбэка,
  /// поэтому воспроизведение с самоподписанным сертификатом всё равно
  /// не заработает. Это ограничение отражено в подсказке настройки.
  final bool trustSelfSignedCertificates;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final timeout = request is http.MultipartRequest
        ? uploadTimeout
        : requestTimeout;
    final completer = Completer<void>();
    final abortable = _withAbortTrigger(request, completer.future);
    return _inner
        .send(abortable)
        .timeout(
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
      // contentLength не переносим: у Request он вычисляется из bodyBytes
      // и сеттер бросает UnsupportedError.
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
    // Неизвестный тип запроса: Abortable-обёртки для него нет, поэтому
    // таймаут не сможет закрыть соединение — запрос уйдёт без триггера
    // отмены.
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
typedef CreatedChopperClient = ({ChopperClient client, http.Client httpClient});

/// Общая инфраструктура создания Chopper-клиентов: базовый
/// [ChopperClient] с [JsonConverter] и переданными интерцепторами.
///
/// Если [httpClient] передан, он используется как есть (общий на несколько
/// клиентов) и закрытием не владеет; иначе создаётся новый [TimeoutHttpClient].
/// Тип — [http.Client], чтобы в тестах можно было инжектировать `MockClient`.
CreatedChopperClient createChopperClient({
  required String baseUrl,
  required List<ChopperService> services,
  List<Interceptor>? interceptors,
  http.Client? httpClient,
}) {
  final resolvedClient = httpClient ?? TimeoutHttpClient();
  final client = ChopperClient(
    baseUrl: Uri.parse(baseUrl),
    services: services,
    client: resolvedClient,
    converter: const JsonConverter(),
    interceptors: interceptors ?? const [],
  );
  return (client: client, httpClient: resolvedClient);
}

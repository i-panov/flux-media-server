import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:http/http.dart' as http;

import 'self_signed_cert_helper.dart';

/// HttpClient, записывающий выставленные настройки: у интерфейса нет
/// геттера `badCertificateCallback`, поэтому прочитать его с настоящего
/// клиента нельзя — только перехватить в момент установки.
class _RecordingHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout;

  bool Function(X509Certificate certificate, String host, int port)?
  recordedCallback;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate certificate, String host, int port)? callback,
  ) => recordedCallback = callback;

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Сервер, который принимает соединение и никогда не отвечает:
/// фиксирует момент, когда клиент закрывает сокет (abort после таймаута).
class _SilentServer {
  new() : _future = ServerSocket.bind(InternetAddress.loopbackIPv4, 0) {
    unawaited(
      _future.then((server) {
        server.listen((socket) {
          socket.listen(
            (_) {},
            onDone: () {
              if (!closedByClient.isCompleted) closedByClient.complete();
            },
            onError: (_) {
              if (!closedByClient.isCompleted) closedByClient.complete();
            },
          );
        });
      }),
    );
  }

  final Future<ServerSocket> _future;
  final closedByClient = Completer<void>();

  Future<int> get port async => (await _future).port;

  Future<void> close() async {
    final s = await _future;
    await s.close();
  }
}

void main() {
  group('TimeoutHttpClient', () {
    test(
      'throws TimeoutException and closes the connection on timeout',
      () async {
        final silent = _SilentServer();
        addTearDown(silent.close);
        final port = await silent.port;

        final client = TimeoutHttpClient(
          requestTimeout: const Duration(milliseconds: 150),
        );
        addTearDown(client.close);

        await expectLater(
          client.get(Uri.parse('http://127.0.0.1:$port/slow')),
          throwsA(isA<TimeoutException>()),
        );

        // Базовый запрос должен быть отменён (соединение реально закрыто).
        await silent.closedByClient.future.timeout(const Duration(seconds: 5));
      },
    );

    test('multipart uploads use the longer timeout', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final serverSub = server.listen((request) {
        request.response.statusCode = 200;
        unawaited(request.response.close());
      });
      addTearDown(serverSub.cancel);

      final client = TimeoutHttpClient(
        uploadTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(milliseconds: 1),
      );
      addTearDown(client.close);

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/upload'),
      )..files.add(http.MultipartFile.fromString('file', 'x' * 1024));

      final response = await client.send(request);
      expect(response.statusCode, 200);
    });

    test('survives a failed request and serves the next one', () async {
      final silent = _SilentServer();
      addTearDown(silent.close);
      final silentPort = await silent.port;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final serverSub = server.listen((request) {
        request.response.statusCode = 200;
        request.response.write('ok');
        unawaited(request.response.close());
      });
      addTearDown(serverSub.cancel);

      final client = TimeoutHttpClient(
        requestTimeout: const Duration(milliseconds: 150),
      );
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('http://127.0.0.1:$silentPort/hang')),
        throwsA(isA<TimeoutException>()),
      );
      await silent.closedByClient.future.timeout(const Duration(seconds: 5));

      // После отменённого запроса клиент ещё жив и отвечает.
      final response = await client.get(
        Uri.parse('http://127.0.0.1:${server.port}/ok'),
      );
      expect(response.statusCode, 200);
    });
  });

  group('trustSelfSignedCertificates wiring', () {
    test('true ставит принимающий колбэк на базовый HttpClient', () {
      _RecordingHttpClient? captured;
      final client = TimeoutHttpClient(
        trustSelfSignedCertificates: true,
        httpClientFactory: () {
          captured = _RecordingHttpClient();
          return captured!;
        },
      );
      addTearDown(client.close);

      expect(captured!.recordedCallback, isNotNull);
    });

    test('false оставляет колбэк пустым', () {
      _RecordingHttpClient? captured;
      final client = TimeoutHttpClient(
        httpClientFactory: () {
          captured = _RecordingHttpClient();
          return captured!;
        },
      );
      addTearDown(client.close);

      expect(captured!.recordedCallback, isNull);
    });

    test('self-signed HTTPS: с доверием проходит, без — падает', () async {
      final cert = await createSelfSignedCert();
      addTearDown(cert.dispose);
      final server = await bindSecureOk(cert.cert, cert.key);
      addTearDown(() => server.close(force: true));
      final uri = Uri.parse('https://127.0.0.1:${server.port}/api/health');

      final trusting = TimeoutHttpClient(trustSelfSignedCertificates: true);
      addTearDown(trusting.close);
      final response = await trusting.get(uri);
      expect(response.statusCode, 200);

      final strict = TimeoutHttpClient();
      addTearDown(strict.close);
      await expectLater(
        strict.get(uri),
        throwsA(
          anyOf(
            isA<HandshakeException>(),
            isA<TlsException>(),
            isA<http.ClientException>(),
          ),
        ),
      );
    });
  });
}

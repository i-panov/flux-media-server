import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/server_health.dart';

import 'self_signed_cert_helper.dart';

/// Health-check через настоящий loopback-сервер: без моков `HttpClient`.
void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  Uri healthUri() => Uri.parse('http://127.0.0.1:${server.port}/api/health');

  group('checkServerHealth', () {
    test('200 OK проходит', () async {
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      await checkServerHealth(healthUri(), trustSelfSigned: false);
    });

    test('не-200 превращается в ServerHealthException с кодом', () async {
      server.listen((request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });

      await expectLater(
        checkServerHealth(healthUri(), trustSelfSigned: false),
        throwsA(
          isA<ServerHealthException>().having(
            (e) => e.statusCode,
            'statusCode',
            HttpStatus.internalServerError,
          ),
        ),
      );
    });

    test('недоступный порт бросает сетевую ошибку', () async {
      final port = server.port;
      await server.close(force: true);

      await expectLater(
        checkServerHealth(
          Uri.parse('http://127.0.0.1:$port/api/health'),
          trustSelfSigned: false,
        ),
        throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
      );
    });

    group('самоподписанный сертификат', () {
      late HttpServer secureServer;
      late String certPath;
      late String keyPath;

      setUpAll(() async {
        // Генерируем самоподписанный серт один раз на файл: openssl есть
        // в dev-окружении, генерить в каждом тесте — медленно.
        final cert = await createSelfSignedCert();
        certPath = cert.cert;
        keyPath = cert.key;
        addTearDown(cert.dispose);
      });

      setUp(() async {
        secureServer = await bindSecureOk(certPath, keyPath);
      });

      tearDown(() => secureServer.close(force: true));

      Uri secureHealthUri() =>
          Uri.parse('https://127.0.0.1:${secureServer.port}/api/health');

      test('без доверия падает на handshake', () async {
        await expectLater(
          checkServerHealth(secureHealthUri(), trustSelfSigned: false),
          throwsA(anyOf(isA<HandshakeException>(), isA<TlsException>())),
        );
      });

      test('с доверием проходит', () async {
        await checkServerHealth(secureHealthUri(), trustSelfSigned: true);
      });
    });
  });
}

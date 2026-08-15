import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:http/http.dart' as http;

/// Сервер, который принимает соединение и никогда не отвечает:
/// фиксирует момент, когда клиент закрывает сокет (abort после таймаута).
class _SilentServer {
  _SilentServer()
      : _future = ServerSocket.bind(InternetAddress.loopbackIPv4, 0) {
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
    });
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
    test('throws TimeoutException and closes the connection on timeout',
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
    });

    test('multipart uploads use the longer timeout', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.statusCode = 200;
        request.response.close();
      });

      final client = TimeoutHttpClient(
        uploadTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(milliseconds: 1),
      );
      addTearDown(client.close);

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/upload'),
      )..files.add(
          http.MultipartFile.fromString('file', 'x' * 1024),
        );

      final response = await client.send(request);
      expect(response.statusCode, 200);
    });

    test('survives a failed request and serves the next one', () async {
      final silent = _SilentServer();
      addTearDown(silent.close);
      final silentPort = await silent.port;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.statusCode = 200;
        request.response.write('ok');
        request.response.close();
      });

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
      final response =
          await client.get(Uri.parse('http://127.0.0.1:${server.port}/ok'));
      expect(response.statusCode, 200);
    });
  });
}

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/backend_version_provider.dart';
import 'package:http/http.dart' as http;

void main() {
  late HttpServer server;
  late ProviderContainer container;

  Future<void> serve(
    Future<void> Function(HttpRequest) onRequest,
  ) async {
    server = await HttpServer.bind('localhost', 0);
    addTearDown(() => server.close(force: true));
    server.listen(onRequest);
    container = ProviderContainer(
      overrides: [
        baseUrlProvider.overrideWithValue(
          'http://localhost:${server.port}/api',
        ),
        directHttpClientProvider.overrideWithValue(http.Client()),
      ],
    );
    addTearDown(() {
      container.read(directHttpClientProvider).close();
      container.dispose();
    });
  }

  group('backendVersionProvider', () {
    test('возвращает версию из /health', () async {
      await serve((req) async {
        expect(req.uri.path, '/api/health');
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"status":"ok","version":"1.2.3"}');
        await req.response.close();
      });

      expect(await container.read(backendVersionProvider.future), '1.2.3');
    });

    test('старый сервер без поля версии — null', () async {
      await serve((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"status":"ok"}');
        await req.response.close();
      });

      expect(await container.read(backendVersionProvider.future), isNull);
    });

    test('недоступный сервер — null, а не ошибка', () async {
      await serve((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });

      expect(await container.read(backendVersionProvider.future), isNull);
    });
  });
}

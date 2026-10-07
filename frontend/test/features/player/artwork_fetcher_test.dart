import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/artwork_fetcher.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Клиент, считающий закрытия: загрузчик обязан закрывать свой
/// короткоживущий клиент на каждый вызов.
class _CloseTrackingClient extends MockClient {
  new(super.fn);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  group('ArtworkFileFetcher.fileNameFor', () {
    test('детерминировано: один URL всегда даёт одно имя', () {
      final uri = Uri.parse('https://host/api/media/7/cover');
      expect(
        ArtworkFileFetcher.fileNameFor(uri),
        ArtworkFileFetcher.fileNameFor(uri),
      );
    });

    test('разные URL дают разные имена', () {
      expect(
        ArtworkFileFetcher.fileNameFor(Uri.parse('https://host/api/a')),
        isNot(ArtworkFileFetcher.fileNameFor(Uri.parse('https://host/api/b'))),
      );
    });

    test('имя начинается с префикса уборки', () {
      expect(
        ArtworkFileFetcher.fileNameFor(Uri.parse('https://host/cover')),
        startsWith('flux_art_'),
      );
    });
  });

  group('ArtworkFileFetcher.call', () {
    test('не-http URL возвращает null без сети', () async {
      var calls = 0;
      final fetcher = ArtworkFileFetcher(
        trustSelfSigned: false,
        // Клиент не должен использоваться вообще.
        clientFactory: () {
          calls++;
          return MockClient((_) async => http.Response('x', 200));
        },
      );

      expect(await fetcher('file:///cover.jpg', null), isNull);
      expect(await fetcher('not a url at all %%', null), isNull);
      expect(calls, 0);
    });

    test('404 возвращает null', () async {
      final fetcher = ArtworkFileFetcher(
        trustSelfSigned: false,
        clientFactory: () =>
            MockClient((_) async => http.Response('nope', 404)),
      );

      expect(await fetcher('https://host/api/media/7/cover', const {}), isNull);
    });

    test('пустое тело возвращает null', () async {
      final fetcher = ArtworkFileFetcher(
        trustSelfSigned: false,
        clientFactory: () => MockClient((_) async => http.Response('', 200)),
      );

      expect(await fetcher('https://host/api/media/7/cover', const {}), isNull);
    });

    test('таймаут возвращает null', () async {
      final fetcher = ArtworkFileFetcher(
        trustSelfSigned: false,
        timeout: const Duration(milliseconds: 50),
        clientFactory: () => MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('x', 200);
        }),
      );

      expect(await fetcher('https://host/api/media/7/cover', const {}), isNull);
    });

    test('200 с байтами сохраняет файл и закрывает клиент', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = await Directory.systemTemp.createTemp('flux_art_test');
      addTearDown(() => tempDir.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getTemporaryDirectory') return tempDir.path;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      late final _CloseTrackingClient client;
      final fetcher = ArtworkFileFetcher(
        trustSelfSigned: false,
        clientFactory: () => client = _CloseTrackingClient(
          (_) async => http.Response.bytes([1, 2, 3], 200),
        ),
      );

      final file = await fetcher('https://host/api/media/7/cover', const {});
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(file.readAsBytesSync(), [1, 2, 3]);
      expect(client.closed, isTrue);
    });
  });
}

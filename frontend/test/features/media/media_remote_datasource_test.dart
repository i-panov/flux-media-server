import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _mediaJson = '''
{"id": 1, "title": "movie.mp4", "type": "video", "file_size": 1024}
''';

late Directory _tempDir;
late File _movieFile;
late File _coverFile;

MediaRemoteDataSource _dataSource({
  required http.Client client,
  String? Function()? authToken,
  Future<String?> Function()? refreshAuth,
}) {
  return MediaRemoteDataSource(
    MediaApiClient.create(baseUrl: 'http://localhost:8080/api').apiClient,
    uploadBaseUrl: 'http://localhost:8080/api',
    authToken: authToken ?? () => 'token',
    refreshAuth: refreshAuth,
    clientFactory: () => client,
  );
}

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('flux_media_ds_test');
    _movieFile = File('${_tempDir.path}/movie.mp4');
    await _movieFile.writeAsBytes(List.filled(1024, 7));
    _coverFile = File('${_tempDir.path}/cover.jpg');
    await _coverFile.writeAsBytes(List.filled(100, 1));
  });

  tearDownAll(() async {
    await _tempDir.delete(recursive: true);
  });

  group('MediaRemoteDataSource.uploadFile auth/refresh', () {
    test('retries once after 401 with the refreshed token', () async {
      var calls = 0;
      var refreshCalls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(
          request.headers['Authorization'],
          calls == 1 ? 'Bearer old-token' : 'Bearer new-token',
        );
        if (calls == 1) {
          return http.Response('{"error": "expired"}', 401);
        }
        return http.Response(_mediaJson, 201);
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'old-token',
        refreshAuth: () async {
          refreshCalls++;
          return 'new-token';
        },
      );

      final media = await dataSource.uploadFile(
        filePath: _movieFile.path,
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(media.id, 1);
      expect(media.title, 'movie.mp4');
      expect(calls, 2);
      expect(refreshCalls, 1);
    });

    test('refresh is not attempted when the user cancelled', () async {
      var refreshCalls = 0;
      final client = MockClient(
        (_) async => http.Response('{"error": "expired"}', 401),
      );

      final dataSource = _dataSource(
        client: client,
        refreshAuth: () async {
          refreshCalls++;
          return 'new-token';
        },
      );

      await expectLater(
        dataSource.uploadFile(
          filePath: _movieFile.path,
          mediaType: 'video',
          fileName: 'movie.mp4',
          isCancelled: () => true,
        ),
        throwsA(isA<UploadCancelledException>()),
      );
      expect(refreshCalls, 0);
    });

    test('failed refresh throws AuthException like the main path', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{"error": "expired"}', 401);
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'expired-token',
        refreshAuth: () async => null,
      );

      await expectLater(
        dataSource.uploadFile(
          filePath: _movieFile.path,
          mediaType: 'video',
          fileName: 'movie.mp4',
        ),
        throwsA(isA<AuthException>()),
      );
      // Refresh не удался — повторный запрос не отправлялся.
      expect(calls, 1);
    });

    test('successful upload cancels the retry loop immediately', () async {
      final client = MockClient(
        (_) async => http.Response(_mediaJson, 201),
      );

      final dataSource = _dataSource(client: client);
      final media = await dataSource.uploadFile(
        filePath: _movieFile.path,
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(media.type, MediaType.video);
    });
  });

  group('MediaRemoteDataSource.uploadCover', () {
    test('sends multipart to /media/{id}/cover with auth header', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{"cover_url": "/api/media/5/cover"}', 200);
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'cover-token',
      );
      await dataSource.uploadCover(5, _coverFile.path);

      expect(captured.url.path, '/api/media/5/cover');
      expect(captured.headers['Authorization'], 'Bearer cover-token');
    });

    test('isCancelled before send aborts with UploadCancelledException',
        () async {
      final client = MockClient(
        (_) async => http.Response('{}', 200),
      );

      final dataSource = _dataSource(
        client: client,
      );

      await expectLater(
        dataSource.uploadCover(5, _coverFile.path, isCancelled: () => true),
        throwsA(isA<UploadCancelledException>()),
      );
    });
  });

  group('MediaRemoteDataSource.uploadFile error mapping', () {
    test('non-JSON response becomes a clear ServerException', () async {
      final client = MockClient(
        (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
      );

      final dataSource = _dataSource(client: client);

      await expectLater(
        dataSource.uploadFile(
          filePath: _movieFile.path,
          mediaType: 'video',
          fileName: 'movie.mp4',
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected server response'),
          ),
        ),
      );
    });

    test('cancellation during the attempt is not masked', () async {
      var cancelled = false;
      final client = MockClient((_) async {
        cancelled = true;
        return http.Response(_mediaJson, 200);
      });

      final dataSource = _dataSource(
        client: client,
      );

      await expectLater(
        dataSource.uploadFile(
          filePath: _movieFile.path,
          mediaType: 'video',
          fileName: 'movie.mp4',
          isCancelled: () => cancelled,
        ),
        throwsA(isA<UploadCancelledException>()),
      );
    });
  });
}

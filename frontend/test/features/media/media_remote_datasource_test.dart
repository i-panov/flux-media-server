import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jobJson = '''
{"job_id": 42}
''';

const _statusJson = '''
{"id": 42, "status": "processing", "error": null, "media": null}
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
    test('returns job id from the 202 response after 401 refresh',
        () async {
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
        return http.Response(_jobJson, 202);
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'old-token',
        refreshAuth: () async {
          refreshCalls++;
          return 'new-token';
        },
      );

      final jobId = await dataSource.uploadFile(
        filePath: _movieFile.path,
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(jobId, 42);
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
        (_) async => http.Response(_jobJson, 202),
      );

      final dataSource = _dataSource(client: client);
      final jobId = await dataSource.uploadFile(
        filePath: _movieFile.path,
        mediaType: 'video',
        fileName: 'movie.mp4',
      );

      expect(jobId, 42);
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

  group('MediaRemoteDataSource artist actions', () {
    test('updateArtistName sends PUT with the new name', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          '{"id": 3, "name": "New Name", "has_cover": false}',
          200,
        );
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'artist-token',
      );
      final body = await dataSource.updateArtistName(3, 'New Name');

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/api/artists/3');
      expect(captured.headers['Authorization'], 'Bearer artist-token');
      expect(captured.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(captured.body), {'name': 'New Name'});
      expect(body['name'], 'New Name');
    });

    test('uploadArtistCover sends multipart to /artists/{id}/cover',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{"ok": true}', 200);
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'cover-token',
      );
      await dataSource.uploadArtistCover(3, _coverFile.path);

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/artists/3/cover');
      expect(captured.headers['Authorization'], 'Bearer cover-token');
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
        return http.Response(_jobJson, 202);
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

  group('MediaRemoteDataSource upload job status/cancel', () {
    test('getUploadJobStatus returns parsed job status', () async {
      final client = MockClient(
        (_) async => http.Response(_statusJson, 200),
      );

      final dataSource = _dataSource(client: client);
      final status = await dataSource.getUploadJobStatus(42);

      expect(status.id, 42);
      expect(status.status, 'processing');
      expect(status.error, isNull);
      expect(status.media, isNull);
    });

    test('getUploadJobStatus sends the job id path', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_statusJson, 200);
      });

      final dataSource = _dataSource(
        client: client,
        authToken: () => 'status-token',
      );
      await dataSource.getUploadJobStatus(7);

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/media/uploads/7');
      expect(captured.headers['Authorization'], 'Bearer status-token');
    });

    test('cancelUploadJob accepts 204 and 409 as success', () async {
      var statusCalls = 0;
      final client = MockClient((request) async {
        statusCalls++;
        if (request.url.path.endsWith('/uploads/1')) {
          return http.Response('', 204);
        }
        return http.Response('', 409);
      });

      final dataSource = _dataSource(client: client);
      await dataSource.cancelUploadJob(1);
      await dataSource.cancelUploadJob(2);

      expect(statusCalls, 2);
    });

    test('cancelUploadJob fails on unexpected status', () async {
      final client = MockClient(
        (_) async => http.Response('{"error": "forbidden"}', 403),
      );

      final dataSource = _dataSource(client: client);

      await expectLater(
        dataSource.cancelUploadJob(1),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            'forbidden',
          ),
        ),
      );
    });
  });
}

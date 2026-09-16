import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/library_api_client.dart';
import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:http/http.dart' as http;

/// Multipart-файл, считающий отправленные байты и поддерживающий отмену.
/// Прогресс недоступен через Chopper, поэтому загрузка выполняется
/// напрямую через `http.MultipartRequest`.
class _CountingMultipartFile extends http.MultipartFile {
  new(
    File file, {
    required String field,
    required String filename,
    required int length,
    void Function(int sent)? onProgress,
    bool Function()? isCancelled,
  }) : super(
         field,
         _buildStream(file, onProgress, isCancelled),
         length,
         filename: filename,
       );

  static Stream<List<int>> _buildStream(
    File file,
    void Function(int sent)? onProgress,
    bool Function()? isCancelled,
  ) {
    return file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          if (isCancelled?.call() ?? false) {
            sink.addError(const UploadCancelledException());
            return;
          }
          onProgress?.call(chunk.length);
          sink.add(chunk);
        },
      ),
    );
  }
}

/// Remote data source for media API calls.
class MediaRemoteDataSource {
  /// Creates a [MediaRemoteDataSource] with the given [apiClient].
  ///
  /// [_libraryApiClient] нужен для `getArtists` (артисты живут в library API).
  /// [_uploadBaseUrl], [_authToken] и [_refreshAuth] используются для
  /// прямой загрузки файлов через http (Chopper не даёт прогресс/отмену).
  /// Провайдеры токенов берутся те же, что у Chopper-перехватчиков
  /// (settingsProvider + authTokenRefresherProvider), чтобы не плодить
  /// второй путь аутентификации.
  /// [clientFactory] инъектируется в тестах.
  new(
    this.apiClient, {
    this._libraryApiClient,
    this._uploadBaseUrl,
    this._authToken,
    this._refreshAuth,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  /// The API client used for HTTP requests.
  final MediaApiClient apiClient;

  final LibraryApiClient? _libraryApiClient;
  final String? _uploadBaseUrl;
  final String? Function()? _authToken;
  final Future<String?> Function()? _refreshAuth;
  final http.Client Function() _clientFactory;

  /// Fetches a paginated list of media items.
  Future<({List<Map<String, dynamic>> items, int total})> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async {
    final response = await apiClient.getMediaList(
      type: type,
      year: year,
      q: q,
      limit: limit,
      offset: offset,
    );
    checkResponse(response, 'Failed to fetch media');
    final body = response.body!;
    return (
      items: (body['items'] as List).cast<Map<String, dynamic>>(),
      total: body['total'] as int,
    );
  }

  /// Fetches a single media item by [id].
  Future<Map<String, dynamic>> getMedia(int id) async {
    final response = await apiClient.getMedia(id);
    checkResponse(response, 'Failed to fetch media');
    return response.body!;
  }

  /// Fetches media items by [ids] in one request (server limit: 100 ids).
  Future<List<Map<String, dynamic>>> getMediaBulk(List<int> ids) async {
    final response = await apiClient.getMediaBulk(ids.join(','));
    checkResponse(response, 'Failed to fetch media');
    final body = response.body!;
    final items = body['items'] as List<dynamic>;
    return items.cast<Map<String, dynamic>>();
  }

  /// Deletes a media item by [id] (file + database record).
  Future<void> deleteMedia(int id) async {
    final response = await apiClient.deleteMedia(id);
    checkResponse(response, 'Failed to delete media');
  }

  /// Fetches all artists.
  Future<List<Artist>> getArtists() async {
    final client = _libraryApiClient;
    if (client == null) {
      throw StateError('libraryApiClient is not configured');
    }
    final response = await client.getArtists();
    checkResponse(response, 'Failed to fetch artists');
    final body = response.body!;
    final items = body['items'] as List<dynamic>;
    return items
        .map((json) => Artist.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Checks if a file with the given [hash] already exists on the server.
  Future<({bool exists, int? mediaId, String? title})> checkHash(
    String hash,
  ) async {
    final response = await apiClient.checkHash({'hash': hash});
    checkResponse(response, 'Failed to check hash');
    final body = response.body!;
    if (body['exists'] == true) {
      final media = body['media'] as Map<String, dynamic>?;
      return (
        exists: true,
        mediaId: media?['id'] as int?,
        title: media?['title'] as String?,
      );
    }
    return (exists: false, mediaId: null, title: null);
  }

  /// Uploads a file to the default library for the given media type.
  ///
  /// Реализовано напрямую через `http.MultipartRequest`, чтобы получать
  /// прогресс отправки ([onProgress]) и уметь отменять загрузку
  /// ([isCancelled]) — Chopper этого не поддерживает.
  ///
  /// Асинхронный контракт: сервер принимает файл и отвечает 202
  /// `{"job_id": N}`; обработка (ffprobe, thumbnails) идёт в фоне,
  /// статус опрашивается через [getUploadJobStatus].
  Future<int> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final file = File(filePath);
    final totalBytes = await file.length();

    var sent = 0;
    void report(int chunkSize) {
      sent += chunkSize;
      onProgress?.call(sent, totalBytes);
    }

    final body = await _postMultipart(
      '/media/upload',
      fields: {'media_type': mediaType},
      // Строим файлы на каждую попытку: MultipartFile можно
      // финализировать только один раз, а retry строит новый запрос.
      createFiles: () => [
        _CountingMultipartFile(
          file,
          field: 'file',
          filename: fileName,
          length: totalBytes,
          onProgress: report,
          isCancelled: isCancelled,
        ),
      ],
      isCancelled: isCancelled,
      onRetry: () => sent = 0,
    );
    return body['job_id'] as int;
  }

  /// Опрашивает статус асинхронного upload-джоба.
  ///
  /// `status`: queued | processing | done | error; при done в поле `media`
  /// приходит готовый объект медиа.
  Future<({int id, String status, String? error, Map<String, dynamic>? media})>
  getUploadJobStatus(int jobId, {bool Function()? isCancelled}) async {
    final body = await _sendJsonRequest(
      'GET',
      '/media/uploads/$jobId',
      isCancelled: isCancelled,
    );
    return (
      id: body!['id'] as int,
      status: body['status'] as String,
      error: body['error'] as String?,
      media: body['media'] as Map<String, dynamic>?,
    );
  }

  /// Отменяет upload-джоб (204). 409 = джоб уже завершён — не ошибка,
  /// отменять нечего.
  Future<void> cancelUploadJob(
    int jobId, {
    bool Function()? isCancelled,
  }) async {
    await _sendJsonRequest(
      'DELETE',
      '/media/uploads/$jobId',
      isCancelled: isCancelled,
      acceptedStatuses: const {204, 409},
    );
  }

  /// Uploads a cover image for a media item.
  ///
  /// В отличие от [uploadFile] ответ тела не разбирается (сервер
  /// возвращает только cover_url), но аутентификация, refresh и отмена
  /// работают так же.
  Future<void> uploadCover(
    int mediaId,
    String filePath, {
    bool Function()? isCancelled,
  }) async {
    final file = File(filePath);
    final length = await file.length();
    await _postMultipart(
      '/media/$mediaId/cover',
      fields: const {},
      createFiles: () => [
        _CountingMultipartFile(
          file,
          field: 'cover',
          filename: filePath.split('/').last,
          length: length,
          isCancelled: isCancelled,
        ),
      ],
      isCancelled: isCancelled,
    );
  }

  /// Переименовывает артиста; возвращает обновлённый объект.
  Future<Map<String, dynamic>> updateArtistName(
    int artistId,
    String name,
  ) async {
    final client = _libraryApiClient;
    if (client == null) {
      throw StateError('libraryApiClient is not configured');
    }
    final response = await client.updateArtist(artistId, {'name': name});
    checkResponse(response, 'Failed to update artist');
    return response.body!;
  }

  /// Загружает обложку артиста (jpg/jpeg/png/webp).
  Future<void> uploadArtistCover(
    int artistId,
    String filePath, {
    bool Function()? isCancelled,
  }) async {
    final file = File(filePath);
    final length = await file.length();
    await _postMultipart(
      '/artists/$artistId/cover',
      fields: const {},
      createFiles: () => [
        _CountingMultipartFile(
          file,
          field: 'cover',
          filename: filePath.split('/').last,
          length: length,
          isCancelled: isCancelled,
        ),
      ],
      isCancelled: isCancelled,
    );
  }

  /// Multipart-POST с тем же контрактом, что у основного пути
  /// (см. [_sendWithAuthRetry]): Bearer-токен из настроек, один refresh
  /// при 401, повторная попытка только если пользователь не отменил
  /// загрузку.
  Future<Map<String, dynamic>> _postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> Function() createFiles,
    bool Function()? isCancelled,
    void Function()? onRetry,
  }) async {
    final body = await _sendWithAuthRetry(
      path,
      (token) {
        final request = http.MultipartRequest('POST', _resolveUrl(path));
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.fields.addAll(fields);
        // Файлы строим на каждую попытку: MultipartFile можно
        // финализировать только один раз, retry требует новый запрос.
        request.files.addAll(createFiles());
        return request;
      },
      isCancelled: isCancelled,
      onRetry: onRetry,
      acceptedStatuses: const {200, 201, 202},
      unexpectedResponseMessage: 'Unexpected server response during upload',
      defaultErrorMessage: 'Failed to upload file',
    );
    return body!;
  }

  /// GET/DELETE с тем же контрактом auth/refresh, что и [_postMultipart]
  /// (см. [_sendWithAuthRetry]).
  Future<Map<String, dynamic>?> _sendJsonRequest(
    String method,
    String path, {
    Map<String, dynamic>? jsonBody,
    bool Function()? isCancelled,
    Set<int> acceptedStatuses = const {200},
  }) {
    return _sendWithAuthRetry(
      path,
      (token) {
        final request = http.Request(method, _resolveUrl(path));
        if (jsonBody != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(jsonBody);
        }
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        return request;
      },
      isCancelled: isCancelled,
      acceptedStatuses: acceptedStatuses,
      allowEmptyBody: true,
    );
  }

  /// База прямых http-запросов: из инъекционного [_uploadBaseUrl] либо
  /// из baseUrl Chopper-клиента. Хвостовой слэш отрезается, чтобы
  /// конкатенация с [path] не давала двойной слэш.
  Uri _resolveUrl(String path) {
    var base = _uploadBaseUrl;
    base ??= apiClient.client.baseUrl.toString();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base$path');
  }

  /// Единый контракт прямых http-запросов в обход Chopper (прогресс
  /// загрузки и отмена недоступны через Chopper):
  /// Bearer-токен из настроек, один refresh при 401 (через тот же
  /// AuthTokenRefresher, что и Chopper-перехватчики), повторная попытка
  /// только если пользователь не отменил операцию, 401 после неудачного
  /// refresh → [AuthException].
  ///
  /// [buildRequest] строит запрос на каждую попытку (тело
  /// MultipartRequest финализируется один раз — retry требует новый).
  Future<Map<String, dynamic>?> _sendWithAuthRetry(
    String path,
    http.BaseRequest Function(String? token) buildRequest, {
    bool Function()? isCancelled,
    void Function()? onRetry,
    Set<int> acceptedStatuses = const {200},
    bool allowEmptyBody = false,
    String unexpectedResponseMessage = 'Unexpected server response',
    String defaultErrorMessage = 'Failed to execute request',
  }) async {
    var token = _authToken?.call();

    for (var attempt = 0; attempt < 2; attempt++) {
      if (isCancelled?.call() ?? false) {
        throw const UploadCancelledException();
      }
      final client = _clientFactory();
      try {
        final streamed = await client.send(buildRequest(token));
        if (isCancelled?.call() ?? false) {
          throw const UploadCancelledException();
        }

        if (streamed.statusCode == 401) {
          if (attempt == 0) {
            final refreshed = await _refreshAuth?.call();
            // Повторная попытка — только если пользователь не отменил
            // операцию, иначе свежий токен уйдёт в никуда.
            if (isCancelled?.call() ?? false) {
              throw const UploadCancelledException();
            }
            if (refreshed != null) {
              token = refreshed;
              onRetry?.call();
              continue;
            }
          }
          throw const AuthException(message: 'Session expired');
        }

        final responseBody = await streamed.stream.bytesToString().timeout(
          const Duration(minutes: 10),
          onTimeout: () => throw const NetworkException(
            message: 'Upload response timed out',
          ),
        );
        if (isCancelled?.call() ?? false) {
          throw const UploadCancelledException();
        }

        // Пустое тело (204) — успех без данных.
        if (allowEmptyBody && responseBody.trim().isEmpty) {
          if (!acceptedStatuses.contains(streamed.statusCode)) {
            throw ServerException(message: defaultErrorMessage);
          }
          return null;
        }

        // 502 от proxy или HTML-ответ — не JSON: не тащим сырой текст
        // в Failure, а отдаём понятное сообщение.
        final Map<String, dynamic> body;
        try {
          body = jsonDecode(responseBody) as Map<String, dynamic>;
        } on FormatException {
          throw ServerException(message: unexpectedResponseMessage);
        }

        if (!acceptedStatuses.contains(streamed.statusCode)) {
          final error = body['error'];
          throw ServerException(
            message: error is String ? error : defaultErrorMessage,
          );
        }
        return body;
      } finally {
        client.close();
      }
    }
    throw ServerException(message: defaultErrorMessage);
  }

  /// Fetches watch progress for all media.
  Future<List<WatchProgress>> getProgress() async {
    final response = await apiClient.getProgress();
    checkResponse(response, 'Failed to fetch progress');
    final body = response.body!;
    final items = body['items'] as List<dynamic>;
    return items
        .map((e) => WatchProgress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Updates metadata for a media item.
  Future<Media> updateMetadata(int mediaId, Map<String, dynamic> data) async {
    final response = await apiClient.updateMetadata(mediaId, data);
    checkResponse(response, 'Failed to update metadata');
    return Media.fromJson(response.body!);
  }

  /// Updates watch progress for a media item.
  Future<WatchProgress> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async {
    final response = await apiClient.updateProgress(mediaId, {
      'position': position,
      'duration': duration,
      'completed': completed,
    });
    checkResponse(response, 'Failed to update progress');
    return WatchProgress.fromJson(response.body!);
  }
}

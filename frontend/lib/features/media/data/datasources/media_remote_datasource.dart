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
  _CountingMultipartFile(
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
  /// [libraryApiClient] нужен для `getArtists` (артисты живут в library API).
  /// [uploadBaseUrl], [authToken] и [refreshAuth] используются для
  /// прямой загрузки файлов через http (Chopper не даёт прогресс/отмену).
  /// Провайдеры токенов берутся те же, что у Chopper-перехватчиков
  /// (settingsProvider + authTokenRefresherProvider), чтобы не плодить
  /// второй путь аутентификации.
  /// [clientFactory] инъектируется в тестах.
  MediaRemoteDataSource(
    this.apiClient, {
    LibraryApiClient? libraryApiClient,
    String? uploadBaseUrl,
    String? Function()? authToken,
    Future<String?> Function()? refreshAuth,
    http.Client Function()? clientFactory,
  })  : _libraryApiClient = libraryApiClient,
        _uploadBaseUrl = uploadBaseUrl,
        _authToken = authToken,
        _refreshAuth = refreshAuth,
        _clientFactory = clientFactory ?? http.Client.new;

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
  Future<Media> uploadFile({
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
    return Media.fromJson(body);
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

  /// Multipart-POST с тем же контрактом, что у основного пути:
  /// Bearer-токен из настроек, один refresh при 401 (через тот же
  /// AuthTokenRefresher, что и Chopper-перехватчики), повторная
  /// попытка только если пользователь не отменил загрузку, 401 после
  /// неудачного refresh → [AuthException].
  Future<Map<String, dynamic>> _postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> Function() createFiles,
    bool Function()? isCancelled,
    void Function()? onRetry,
  }) async {
    final baseUrl = _uploadBaseUrl ??
        apiClient.client.baseUrl.toString().replaceFirst(RegExp(r'/$'), '');
    var token = _authToken?.call();

    for (var attempt = 0; attempt < 2; attempt++) {
      if (isCancelled?.call() ?? false) {
        throw const UploadCancelledException();
      }
      final client = _clientFactory();
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl$path'),
        );
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.fields.addAll(fields);
        request.files.addAll(createFiles());

        final streamed = await client.send(request);
        if (isCancelled?.call() ?? false) {
          throw const UploadCancelledException();
        }

        if (streamed.statusCode == 401) {
          if (attempt == 0) {
            final refreshed = await _refreshAuth?.call();
            // Повторная попытка — только если пользователь не отменил
            // загрузку, иначе свежий токен уйдёт в никуда.
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

        final responseBody =
            await streamed.stream.bytesToString().timeout(
                  const Duration(minutes: 10),
                  onTimeout: () => throw const NetworkException(
                    message: 'Upload response timed out',
                  ),
                );
        if (isCancelled?.call() ?? false) {
          throw const UploadCancelledException();
        }

        // 502 от proxy или HTML-ответ — не JSON: не тащим сырой текст
        // в Failure, а отдаём понятное сообщение.
        final Map<String, dynamic> body;
        try {
          body = jsonDecode(responseBody) as Map<String, dynamic>;
        } on FormatException {
          throw const ServerException(
            message: 'Unexpected server response during upload',
          );
        }

        if (streamed.statusCode != 200 && streamed.statusCode != 201) {
          final error = body['error'];
          throw ServerException(
            message: error is String ? error : 'Failed to upload file',
          );
        }
        return body;
      } finally {
        client.close();
      }
    }
    throw const ServerException(message: 'Failed to upload file');
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
    final response = await apiClient.updateProgress(
      mediaId,
      {
        'position': position,
        'duration': duration,
        'completed': completed,
      },
    );
    checkResponse(response, 'Failed to update progress');
    return WatchProgress.fromJson(response.body!);
  }
}

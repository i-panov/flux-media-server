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
import 'package:http/http.dart' show MultipartFile;

/// Загрузка отменена пользователем.
class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

/// Multipart-файл, считающий отправленные байты и поддерживающий отмену.
/// Прогресс недоступен через Chopper, поэтому загрузка выполняется
/// напрямую через `http.MultipartRequest`.
class _CountingMultipartFile extends http.MultipartFile {
  _CountingMultipartFile(
    File file, {
    required String field,
    required String filename,
    required int length,
    required void Function(int sent) onProgress,
    required bool Function()? isCancelled,
  }) : super(
          field,
          _buildStream(file, onProgress, isCancelled),
          length,
          filename: filename,
        );

  static Stream<List<int>> _buildStream(
    File file,
    void Function(int sent) onProgress,
    bool Function()? isCancelled,
  ) {
    return file.openRead().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              if (isCancelled?.call() ?? false) {
                sink.addError(const UploadCancelledException());
                return;
              }
              onProgress(chunk.length);
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
  MediaRemoteDataSource(
    this.apiClient, {
    LibraryApiClient? libraryApiClient,
    String? uploadBaseUrl,
    String? Function()? authToken,
    Future<String?> Function()? refreshAuth,
  })  : _libraryApiClient = libraryApiClient,
        _uploadBaseUrl = uploadBaseUrl,
        _authToken = authToken,
        _refreshAuth = refreshAuth;

  /// The API client used for HTTP requests.
  final MediaApiClient apiClient;

  final LibraryApiClient? _libraryApiClient;
  final String? _uploadBaseUrl;
  final String? Function()? _authToken;
  final Future<String?> Function()? _refreshAuth;

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
    final baseUrl = _uploadBaseUrl ??
        apiClient.client.baseUrl.toString().replaceFirst(RegExp(r'/$'), '');
    var token = _authToken?.call();

    var sent = 0;
    void report(int chunkSize) {
      sent += chunkSize;
      onProgress?.call(sent, totalBytes);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final client = http.Client();
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/media/upload'),
        );
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.fields['media_type'] = mediaType;
        request.files.add(
          _CountingMultipartFile(
            file,
            field: 'file',
            filename: fileName,
            length: totalBytes,
            onProgress: report,
            isCancelled: isCancelled,
          ),
        );

        final streamed = await client.send(request);
        if (isCancelled?.call() ?? false) {
          throw const UploadCancelledException();
        }

        if (streamed.statusCode == 401 && attempt == 0) {
          final refreshed = await _refreshAuth?.call();
          if (refreshed != null) {
            token = refreshed;
            sent = 0;
            continue;
          }
          throw const AuthException(message: 'Session expired');
        }

        final responseBody =
            await streamed.stream.bytesToString().timeout(
                  const Duration(minutes: 10),
                  onTimeout: () => throw Exception('Upload response timed out'),
                );
        if (isCancelled?.call() ?? false) {
          throw const UploadCancelledException();
        }

        final body = jsonDecode(responseBody) as Map<String, dynamic>;
        if (streamed.statusCode != 200 && streamed.statusCode != 201) {
          final error = body['error'];
          throw ServerException(
            message: error is String ? error : 'Failed to upload file',
          );
        }
        return Media.fromJson(body);
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

  /// Uploads a cover image for a media item.
  Future<void> uploadCover(int mediaId, String filePath) async {
    final cover = await MultipartFile.fromPath('cover', filePath);
    final response = await apiClient.uploadCover(mediaId, cover);
    checkResponse(response, 'Failed to upload cover');
  }
}

import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:http/http.dart' show MultipartFile;

/// Remote data source for media API calls.
class MediaRemoteDataSource {
  /// Creates a [MediaRemoteDataSource] with the given [apiClient].
  MediaRemoteDataSource(this.apiClient);

  /// The API client used for HTTP requests.
  final ApiClient apiClient;

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
  Future<Media> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
  }) async {
    final file = await MultipartFile.fromPath(
      'file',
      filePath,
      filename: fileName,
    );
    final response = await apiClient.uploadMedia(
      mediaType,
      file,
    );
    checkResponse(response, 'Failed to upload file');
    return Media.fromJson(response.body!);
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
  }) async {
    final response = await apiClient.updateProgress(
      mediaId,
      {'position': position},
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

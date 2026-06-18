import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';

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
    int? limit,
    int? offset,
  }) async {
    final Response<Map<String, dynamic>> response = await apiClient.getMediaList(
      type: type,
      year: year,
      limit: limit,
      offset: offset,
    );
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] as String? ?? 'Failed to fetch media',
      );
    }
    final body = response.body!;
    return (
      items: (body['items'] as List).cast<Map<String, dynamic>>(),
      total: body['total'] as int,
    );
  }

  /// Fetches a single media item by [id].
  Future<Map<String, dynamic>> getMedia(int id) async {
    final Response<Map<String, dynamic>> response = await apiClient.getMedia(id);
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] as String? ?? 'Failed to fetch media',
      );
    }
    return response.body!;
  }
}

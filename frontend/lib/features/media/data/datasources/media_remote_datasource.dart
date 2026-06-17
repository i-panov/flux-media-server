import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';

class MediaRemoteDataSource {
  MediaRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<({List<Map<String, dynamic>> items, int total})> getMediaList({
    String? type,
    int? year,
    int? limit,
    int? offset,
  }) async {
    final response = await apiClient.getMediaList(
      type: type,
      year: year,
      limit: limit,
      offset: offset,
    );
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] ?? 'Failed to fetch media',
      );
    }
    final body = response.body!;
    final items = (body['items'] as List).cast<Map<String, dynamic>>();
    final total = body['total'] as int;
    return (items: items, total: total);
  }

  Future<Map<String, dynamic>> getMedia(int id) async {
    final response = await apiClient.getMedia(id);
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] ?? 'Failed to fetch media',
      );
    }
    return response.body!;
  }
}

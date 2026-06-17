import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';

class LibraryRemoteDataSource {
  LibraryRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<List<Map<String, dynamic>>> getLibraries() async {
    final response = await apiClient.getLibraries();
    if (response.statusCode != 200) {
      throw ServerException(
        message: 'Failed to fetch libraries',
      );
    }
    final body = response.body!;
    return body.cast<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> scanLibrary(int id) async {
    final response = await apiClient.scanLibrary(id);
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] ?? 'Failed to scan library',
      );
    }
    return response.body!;
  }
}

import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';

/// Remote data source for library API calls.
class LibraryRemoteDataSource {
  /// Creates a [LibraryRemoteDataSource] with the given [apiClient].
  LibraryRemoteDataSource(this.apiClient);

  /// The API client used for HTTP requests.
  final ApiClient apiClient;

  /// Fetches all libraries from the server.
  Future<List<Map<String, dynamic>>> getLibraries() async {
    final Response<List<dynamic>> response = await apiClient.getLibraries();
    if (response.statusCode != 200) {
      throw const ServerException(message: 'Failed to fetch libraries');
    }
    return response.body!.cast<Map<String, dynamic>>().toList();
  }

  /// Triggers a scan of the library with the given [id].
  Future<Map<String, dynamic>> scanLibrary(int id) async {
    final Response<Map<String, dynamic>> response =
        await apiClient.scanLibrary(id);
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] as String? ?? 'Failed to scan library',
      );
    }
    return response.body!;
  }
}

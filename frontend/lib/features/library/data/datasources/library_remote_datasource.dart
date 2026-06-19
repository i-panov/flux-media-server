import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';

void _checkStatus(Response<dynamic> response, String defaultMessage) {
  if (response.statusCode == 401) {
    throw const AuthException(message: 'Session expired');
  }
  if (response.statusCode != 200) {
    throw ServerException(
      message: response.body?['error'] as String? ?? defaultMessage,
    );
  }
}

/// Remote data source for library API calls.
class LibraryRemoteDataSource {
  /// Creates a [LibraryRemoteDataSource] with the given [apiClient].
  LibraryRemoteDataSource(this.apiClient);

  /// The API client used for HTTP requests.
  final ApiClient apiClient;

  /// Fetches all libraries from the server.
  Future<List<Map<String, dynamic>>> getLibraries() async {
    final Response<List<dynamic>> response = await apiClient.getLibraries();
    _checkStatus(response, 'Failed to fetch libraries');
    return response.body!.cast<Map<String, dynamic>>().toList();
  }

  /// Triggers a scan of the library with the given [id].
  Future<Map<String, dynamic>> scanLibrary(int id) async {
    final Response<Map<String, dynamic>> response =
        await apiClient.scanLibrary(id);
    _checkStatus(response, 'Failed to scan library');
    return response.body!;
  }
}

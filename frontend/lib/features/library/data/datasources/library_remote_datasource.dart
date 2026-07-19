import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';

/// Remote data source for library API calls.
class LibraryRemoteDataSource {
  /// Creates a [LibraryRemoteDataSource] with the given [apiClient].
  LibraryRemoteDataSource(this.apiClient);

  /// The API client used for HTTP requests.
  final ApiClient apiClient;

  /// Fetches all libraries from the server.
  Future<List<Map<String, dynamic>>> getLibraries() async {
    final Response<List<dynamic>> response = await apiClient.getLibraries();
    checkResponse(response, 'Failed to fetch libraries');
    return response.body!.cast<Map<String, dynamic>>().toList();
  }

  /// Triggers a scan of the library with the given [id].
  /// Returns the response message.
  Future<String> scanLibrary(int id) async {
    final Response<Map<String, dynamic>> response =
        await apiClient.scanLibrary(id);
    checkResponse(response, 'Failed to scan library');
    return response.body!['message'] as String? ?? 'Scan started';
  }

  /// Gets the scan status for the library with the given [id].
  Future<Map<String, dynamic>> getScanStatus(int id) async {
    final Response<Map<String, dynamic>> response =
        await apiClient.getScanStatus(id);
    checkResponse(response, 'Failed to get scan status');
    return response.body!;
  }
}

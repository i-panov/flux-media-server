import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRemoteDataSource {
  FavoritesRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<List<Favorite>> getFavorites({String? type}) async {
    final response = await apiClient.getFavorites(type: type);
    checkResponse(response, 'Failed to fetch favorites');
    final body = response.body!;
    return body
        .map((json) => Favorite.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Favorite> addFavorite(int mediaId) async {
    final response = await apiClient.addFavorite(mediaId);
    checkResponse(response, 'Failed to add favorite');
    return Favorite.fromJson(response.body!);
  }

  Future<void> removeFavorite(int mediaId) async {
    final response = await apiClient.removeFavorite(mediaId);
    checkResponse(response, 'Failed to remove favorite');
  }

  Future<Favorite> addArtistFavorite(String artistName) async {
    final response =
        await apiClient.addArtistFavorite({'artist': artistName});
    checkResponse(response, 'Failed to add artist favorite');
    return Favorite.fromJson(response.body!);
  }

  Future<void> removeArtistFavorite(String artistName) async {
    final response = await apiClient.removeArtistFavorite(artistName);
    checkResponse(response, 'Failed to remove artist favorite');
  }
}

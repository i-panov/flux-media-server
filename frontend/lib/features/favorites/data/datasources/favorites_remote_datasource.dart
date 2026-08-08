import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRemoteDataSource {
  FavoritesRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<List<Favorite>> getFavorites() async {
    final response = await apiClient.getFavorites();
    checkResponse(response, 'Failed to fetch favorites');
    final body = response.body!;
    final items = body['items'] as List<dynamic>;
    return items
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

  Future<Favorite> addArtistFavorite(int artistId) async {
    final response =
        await apiClient.addArtistFavorite({'artist_id': artistId});
    checkResponse(response, 'Failed to add artist favorite');
    return Favorite.fromJson(response.body!);
  }

  Future<void> removeArtistFavorite(int artistId) async {
    final response = await apiClient.removeArtistFavorite(artistId);
    checkResponse(response, 'Failed to remove artist favorite');
  }
}

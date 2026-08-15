import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/library_api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRemoteDataSource {
  FavoritesRemoteDataSource(this.apiClient);

  final LibraryApiClient apiClient;

  Future<List<Favorite>> getFavorites() async {
    final response = await apiClient.getFavorites();
    checkResponse(response, 'Failed to fetch favorites');
    final items = _bodyListField(
      response,
      'items',
      'Failed to fetch favorites',
    );
    final favorites = <Favorite>[];
    for (final json in items) {
      if (json is! Map<String, dynamic>) {
        throw const ServerException(message: 'Malformed favorite item');
      }
      favorites.add(Favorite.fromJson(json));
    }
    return favorites;
  }

  Future<Favorite> addFavorite(int mediaId) async {
    final response = await apiClient.addFavorite(mediaId);
    checkResponse(response, 'Failed to add favorite');
    return _favoriteFromBody(response, 'Failed to add favorite');
  }

  Future<void> removeFavorite(int mediaId) async {
    final response = await apiClient.removeFavorite(mediaId);
    checkResponse(response, 'Failed to remove favorite');
  }

  Future<Favorite> addArtistFavorite(int artistId) async {
    final response = await apiClient.addArtistFavorite({'artist_id': artistId});
    checkResponse(response, 'Failed to add artist favorite');
    return _favoriteFromBody(response, 'Failed to add artist favorite');
  }

  Future<void> removeArtistFavorite(int artistId) async {
    final response = await apiClient.removeArtistFavorite(artistId);
    checkResponse(response, 'Failed to remove artist favorite');
  }

  List<dynamic> _bodyListField(
    Response<dynamic> response,
    String field,
    String message,
  ) {
    final body = response.body;
    if (body is! Map<String, dynamic> || body[field] is! List) {
      throw ServerException(message: 'Malformed response: $message');
    }
    return body[field] as List<dynamic>;
  }

  Favorite _favoriteFromBody(Response<dynamic> response, String message) {
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw ServerException(message: 'Malformed response: $message');
    }
    return Favorite.fromJson(body);
  }
}

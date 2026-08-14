// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_api_client.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
final class _$LibraryApiClient extends LibraryApiClient {
  _$LibraryApiClient([ChopperClient? client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final Type definitionType = LibraryApiClient;

  @override
  Future<Response<Map<String, dynamic>>> addFavorite(int id) {
    final Uri $url = Uri.parse('/media/${id}/favorite');
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> removeFavorite(int id) {
    final Uri $url = Uri.parse('/media/${id}/favorite');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> getFavorites() {
    final Uri $url = Uri.parse('/favorites');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> addArtistFavorite(
      Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/favorites/artist');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> removeArtistFavorite(int artistId) {
    final Uri $url = Uri.parse('/favorites/artist');
    final Map<String, dynamic> $params = <String, dynamic>{
      'artist_id': artistId
    };
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> getArtists() {
    final Uri $url = Uri.parse('/artists');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> createCollection(
      Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/collections');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<List<dynamic>>> getCollections() {
    final Uri $url = Uri.parse('/collections');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<List<dynamic>, List<dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> updateCollection(
    int id,
    Map<String, dynamic> body,
  ) {
    final Uri $url = Uri.parse('/collections/${id}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> deleteCollection(int id) {
    final Uri $url = Uri.parse('/collections/${id}');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> addCollectionItem(
    int id,
    Map<String, dynamic> body,
  ) {
    final Uri $url = Uri.parse('/collections/${id}/items');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> removeCollectionItem(
    int id,
    int mediaId,
  ) {
    final Uri $url = Uri.parse('/collections/${id}/items/${mediaId}');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<List<dynamic>>> getCollectionItems(int id) {
    final Uri $url = Uri.parse('/collections/${id}/items');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<List<dynamic>, List<dynamic>>($request);
  }
}

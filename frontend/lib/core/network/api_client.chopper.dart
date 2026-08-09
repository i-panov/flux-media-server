// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_client.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
final class _$ApiClient extends ApiClient {
  _$ApiClient([ChopperClient? client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final Type definitionType = ApiClient;

  @override
  Future<Response<Map<String, dynamic>>> requestCode(
      Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/auth/request-code');
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
  Future<Response<Map<String, dynamic>>> verifyCode(Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/auth/verify-code');
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
  Future<Response<Map<String, dynamic>>> refreshToken(
      Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/auth/refresh');
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
  Future<Response<Map<String, dynamic>>> getMe() {
    final Uri $url = Uri.parse('/auth/me');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) {
    final Uri $url = Uri.parse('/media');
    final Map<String, dynamic> $params = <String, dynamic>{
      'type': type,
      'year': year,
      'q': q,
      'limit': limit,
      'offset': offset,
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> getMedia(int id) {
    final Uri $url = Uri.parse('/media/${id}');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> deleteMedia(int id) {
    final Uri $url = Uri.parse('/media/${id}');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> checkHash(Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/media/check-hash');
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
  Future<Response<Map<String, dynamic>>> uploadMedia(
    String mediaType,
    MultipartFile file,
  ) {
    final Uri $url = Uri.parse('/media/upload');
    final List<PartValue> $parts = <PartValue>[
      PartValue<String>(
        'media_type',
        mediaType,
      ),
      PartValueFile<MultipartFile>(
        'file',
        file,
      ),
    ];
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      parts: $parts,
      multipart: true,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> uploadCover(
    int id,
    MultipartFile cover,
  ) {
    final Uri $url = Uri.parse('/media/${id}/cover');
    final List<PartValue> $parts = <PartValue>[
      PartValueFile<MultipartFile>(
        'cover',
        cover,
      )
    ];
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      parts: $parts,
      multipart: true,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

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

  @override
  Future<Response<Map<String, dynamic>>> getProgress() {
    final Uri $url = Uri.parse('/progress');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> updateProgress(
    int mediaId,
    Map<String, dynamic> body,
  ) {
    final Uri $url = Uri.parse('/progress/${mediaId}');
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
  Future<Response<Map<String, dynamic>>> getLyrics(int id) {
    final Uri $url = Uri.parse('/media/${id}/lyrics');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> upsertLyrics(
    int id,
    Map<String, dynamic> body,
  ) {
    final Uri $url = Uri.parse('/media/${id}/lyrics');
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
  Future<Response<Map<String, dynamic>>> updateMetadata(
    int mediaId,
    Map<String, dynamic> body,
  ) {
    final Uri $url = Uri.parse('/metadata/${mediaId}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }
}

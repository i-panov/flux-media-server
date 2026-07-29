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
    int libraryId,
    MultipartFile file,
  ) {
    final Uri $url = Uri.parse('/media/upload');
    final List<PartValue> $parts = <PartValue>[
      PartValue<int>(
        'library_id',
        libraryId,
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
  Future<Response<Uint8List>> getThumbnail(int id) {
    final Uri $url = Uri.parse('/media/${id}/thumb');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<Uint8List, Uint8List>($request);
  }

  @override
  Future<Response<List<dynamic>>> getLibraries() {
    final Uri $url = Uri.parse('/libraries');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<List<dynamic>, List<dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> createLibrary(
      Map<String, dynamic> body) {
    final Uri $url = Uri.parse('/libraries');
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
  Future<Response<Map<String, dynamic>>> updateLibrary(
    int id,
    Map<String, dynamic> body,
  ) {
    final Uri $url = Uri.parse('/libraries/${id}');
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
  Future<Response<Map<String, dynamic>>> deleteLibrary(int id) {
    final Uri $url = Uri.parse('/libraries/${id}');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> scanLibrary(int id) {
    final Uri $url = Uri.parse('/libraries/${id}/scan');
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
    );
    return client.send<Map<String, dynamic>, Map<String, dynamic>>($request);
  }

  @override
  Future<Response<Map<String, dynamic>>> getScanStatus(int id) {
    final Uri $url = Uri.parse('/libraries/${id}/scan-status');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
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
  Future<Response<List<dynamic>>> getFavorites({String? type}) {
    final Uri $url = Uri.parse('/favorites');
    final Map<String, dynamic> $params = <String, dynamic>{'type': type};
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
    );
    return client.send<List<dynamic>, List<dynamic>>($request);
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
  Future<Response<Map<String, dynamic>>> removeArtistFavorite(String artist) {
    final Uri $url = Uri.parse('/favorites/artist');
    final Map<String, dynamic> $params = <String, dynamic>{'artist': artist};
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      parameters: $params,
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
  Future<Response<List<dynamic>>> getProgress() {
    final Uri $url = Uri.parse('/progress');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
    );
    return client.send<List<dynamic>, List<dynamic>>($request);
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

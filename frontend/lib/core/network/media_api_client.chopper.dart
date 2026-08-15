// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_api_client.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
final class _$MediaApiClient extends MediaApiClient {
  _$MediaApiClient([ChopperClient? client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final Type definitionType = MediaApiClient;

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
  Future<Response<Map<String, dynamic>>> getMediaBulk(String ids) {
    final Uri $url = Uri.parse('/media/bulk');
    final Map<String, dynamic> $params = <String, dynamic>{'ids': ids};
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
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

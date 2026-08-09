import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/safe_logging_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show MultipartFile;
import 'package:http/io_client.dart' show IOClient;

part 'api_client.chopper.dart';

class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient()
      : _inner = IOClient(
          HttpClient()..connectionTimeout = const Duration(seconds: 10),
        );

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      if (request is http.MultipartRequest) {
        // Multipart uploads can be large — use longer timeout.
        return _inner.send(request).timeout(const Duration(seconds: 120));
      }
      return _inner.send(request).timeout(const Duration(seconds: 30));
    } finally {
      // The inner HttpClient is created once per _TimeoutHttpClient instance
      // and reused across requests. It should NOT be closed per-request.
    }
  }

  /// Close the inner HttpClient to release sockets.
  @override
  void close() {
    _inner.close();
  }
}

@ChopperApi()
abstract class ApiClient extends ChopperService {
  static ApiClient create({
    String? baseUrl,
    AuthInterceptor? authInterceptor,
    TokenRefreshInterceptor? tokenRefreshInterceptor,
  }) {
    final client = ChopperClient(
      baseUrl: Uri.parse(baseUrl ?? 'http://localhost:8080/api'),
      services: [_$ApiClient()],
      client: _TimeoutHttpClient(),
      converter: const JsonConverter(),
      interceptors: [
        if (authInterceptor != null) authInterceptor,
        if (tokenRefreshInterceptor != null) tokenRefreshInterceptor,
        SafeLoggingInterceptor(),
      ],
    );
    return _$ApiClient(client);
  }

  // Auth
  @Post(path: '/auth/request-code')
  Future<Response<Map<String, dynamic>>> requestCode(
    @Body() Map<String, dynamic> body,
  );

  @Post(path: '/auth/verify-code')
  Future<Response<Map<String, dynamic>>> verifyCode(
    @Body() Map<String, dynamic> body,
  );

  @Post(path: '/auth/refresh')
  Future<Response<Map<String, dynamic>>> refreshToken(
    @Body() Map<String, dynamic> body,
  );

  @Get(path: '/auth/me')
  Future<Response<Map<String, dynamic>>> getMe();

  // Media
  @Get(path: '/media')
  Future<Response<Map<String, dynamic>>> getMediaList({
    @Query('type') String? type,
    @Query('year') int? year,
    @Query('q') String? q,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @Get(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> getMedia(@Path('id') int id);

  @Delete(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> deleteMedia(@Path('id') int id);

  @Post(path: '/media/check-hash')
  Future<Response<Map<String, dynamic>>> checkHash(
    @Body() Map<String, dynamic> body,
  );

  @Post(path: '/media/upload')
  @multipart
  Future<Response<Map<String, dynamic>>> uploadMedia(
    @Part('media_type') String mediaType,
    @PartFile('file') MultipartFile file,
  );

  @Put(path: '/media/{id}/cover')
  @multipart
  Future<Response<Map<String, dynamic>>> uploadCover(
    @Path('id') int id,
    @PartFile('cover') MultipartFile cover,
  );

  // Favorites
  @Post(path: '/media/{id}/favorite', optionalBody: true)
  Future<Response<Map<String, dynamic>>> addFavorite(@Path('id') int id);

  @Delete(path: '/media/{id}/favorite')
  Future<Response<Map<String, dynamic>>> removeFavorite(@Path('id') int id);

  @Get(path: '/favorites')
  Future<Response<Map<String, dynamic>>> getFavorites();

  @Post(path: '/favorites/artist')
  Future<Response<Map<String, dynamic>>> addArtistFavorite(
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/favorites/artist')
  Future<Response<Map<String, dynamic>>> removeArtistFavorite(
    @Query('artist_id') int artistId,
  );

  // Artists
  @Get(path: '/artists')
  Future<Response<Map<String, dynamic>>> getArtists();

  // Collections
  @Post(path: '/collections')
  Future<Response<Map<String, dynamic>>> createCollection(
    @Body() Map<String, dynamic> body,
  );

  @Get(path: '/collections')
  Future<Response<List<dynamic>>> getCollections();

  @Put(path: '/collections/{id}')
  Future<Response<Map<String, dynamic>>> updateCollection(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/collections/{id}')
  Future<Response<Map<String, dynamic>>> deleteCollection(@Path('id') int id);

  @Post(path: '/collections/{id}/items')
  Future<Response<Map<String, dynamic>>> addCollectionItem(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/collections/{id}/items/{mediaId}')
  Future<Response<Map<String, dynamic>>> removeCollectionItem(
    @Path('id') int id,
    @Path('mediaId') int mediaId,
  );

  @Get(path: '/collections/{id}/items')
  Future<Response<List<dynamic>>> getCollectionItems(@Path('id') int id);

  // Progress
  @Get(path: '/progress')
  Future<Response<Map<String, dynamic>>> getProgress();

  @Put(path: '/progress/{mediaId}')
  Future<Response<Map<String, dynamic>>> updateProgress(
    @Path('mediaId') int mediaId,
    @Body() Map<String, dynamic> body,
  );

  // Lyrics
  @Get(path: '/media/{id}/lyrics')
  Future<Response<Map<String, dynamic>>> getLyrics(@Path('id') int id);

  @Put(path: '/media/{id}/lyrics')
  Future<Response<Map<String, dynamic>>> upsertLyrics(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  // Metadata
  @Put(path: '/metadata/{mediaId}')
  Future<Response<Map<String, dynamic>>> updateMetadata(
    @Path('mediaId') int mediaId,
    @Body() Map<String, dynamic> body,
  );
}

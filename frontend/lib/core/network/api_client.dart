import 'dart:typed_data';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' show MultipartFile;

import 'interceptors/auth_interceptor.dart';
import 'interceptors/safe_logging_interceptor.dart';

part 'api_client.chopper.dart';

@ChopperApi()
abstract class ApiClient extends ChopperService {
  static ApiClient create({String? baseUrl, AuthInterceptor? authInterceptor}) {
    final client = ChopperClient(
      baseUrl: Uri.parse(baseUrl ?? 'http://localhost:8080/api'),
      services: [_$ApiClient()],
      converter: JsonConverter(),
      interceptors: [
        if (authInterceptor != null) authInterceptor,
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

  @Post(path: '/media/check-hash')
  Future<Response<Map<String, dynamic>>> checkHash(
    @Body() Map<String, dynamic> body,
  );

  @Post(path: '/media/upload')
  @multipart
  Future<Response<Map<String, dynamic>>> uploadMedia(
    @Part('library_id') int libraryId,
    @PartFile('file') MultipartFile file,
  );

  @Get(path: '/media/{id}/thumb')
  Future<Response<Uint8List>> getThumbnail(@Path('id') int id);

  // Libraries
  @Get(path: '/libraries')
  Future<Response<List<dynamic>>> getLibraries();

  @Post(path: '/libraries')
  Future<Response<Map<String, dynamic>>> createLibrary(
    @Body() Map<String, dynamic> body,
  );

  @Put(path: '/libraries/{id}')
  Future<Response<Map<String, dynamic>>> updateLibrary(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/libraries/{id}')
  Future<Response<Map<String, dynamic>>> deleteLibrary(@Path('id') int id);

  @Post(path: '/libraries/{id}/scan', optionalBody: true)
  Future<Response<Map<String, dynamic>>> scanLibrary(@Path('id') int id);

  @Get(path: '/libraries/{id}/scan-status')
  Future<Response<Map<String, dynamic>>> getScanStatus(@Path('id') int id);

  // Favorites
  @Post(path: '/media/{id}/favorite', optionalBody: true)
  Future<Response<Map<String, dynamic>>> addFavorite(@Path('id') int id);

  @Delete(path: '/media/{id}/favorite')
  Future<Response<Map<String, dynamic>>> removeFavorite(@Path('id') int id);

  @Get(path: '/favorites')
  Future<Response<List<dynamic>>> getFavorites({
    @Query('type') String? type,
  });

  @Post(path: '/favorites/artist')
  Future<Response<Map<String, dynamic>>> addArtistFavorite(
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/favorites/artist')
  Future<Response<Map<String, dynamic>>> removeArtistFavorite(
    @Query('artist') String artist,
  );

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
  Future<Response<List<dynamic>>> getProgress();

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
}

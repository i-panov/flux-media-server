import 'dart:typed_data';

import 'package:chopper/chopper.dart';

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
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @Get(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> getMedia(@Path('id') int id);

  @Post(path: '/media')
  Future<Response<Map<String, dynamic>>> createMedia(
    @Body() Map<String, dynamic> body,
  );

  @Put(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> updateMedia(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> deleteMedia(@Path('id') int id);

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

  @Post(path: '/libraries/{id}/scan')
  Future<Response<Map<String, dynamic>>> scanLibrary(@Path('id') int id);

  // Progress
  @Get(path: '/progress')
  Future<Response<List<dynamic>>> getProgress();

  @Put(path: '/progress/{mediaId}')
  Future<Response<Map<String, dynamic>>> updateProgress(
    @Path('mediaId') int mediaId,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/progress/{mediaId}')
  Future<Response<Map<String, dynamic>>> deleteProgress(@Path('mediaId') int mediaId);

  // Metadata
  @Get(path: '/metadata/search')
  Future<Response<Map<String, dynamic>>> searchMetadata(@Query('q') String query);

  @Post(path: '/metadata/{mediaId}/refresh')
  Future<Response<Map<String, dynamic>>> refreshMetadata(@Path('mediaId') int mediaId);

  @Put(path: '/metadata/{mediaId}')
  Future<Response<Map<String, dynamic>>> updateMetadata(
    @Path('mediaId') int mediaId,
    @Body() Map<String, dynamic> body,
  );
}

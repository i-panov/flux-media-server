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
}

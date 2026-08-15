import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:http/http.dart' show MultipartFile;

part 'media_api_client.chopper.dart';

/// Результат создания [MediaApiClient]: сервис и низкоуровневый
/// HTTP-клиент, который нужно закрыть через `ref.onDispose`.
typedef MediaApiClientBundle = ({
  MediaApiClient apiClient,
  TimeoutHttpClient httpClient,
});

/// Chopper-сервис медиа: CRUD, загрузка, hash, прогресс,
/// тексты песен, метаданные, обложки.
///
/// Пути объявлены относительно baseUrl, который уже включает `/api`.
@ChopperApi()
abstract class MediaApiClient extends ChopperService {
  /// Создаёт сервис вместе с его HTTP-клиентом.
  static MediaApiClientBundle create({
    String? baseUrl,
    Iterable<dynamic>? interceptors,
  }) {
    final created = createChopperClient(
      baseUrl: baseUrl ?? 'http://localhost:8080/api',
      services: [_$MediaApiClient()],
      interceptors: interceptors,
    );
    return (
      apiClient: _$MediaApiClient(created.client),
      httpClient: created.httpClient,
    );
  }

  /// Привязывает сервис к существующему [ChopperClient] (общему для всех
  /// сервисов приложения). В отличие от [create], не создаёт собственный
  /// HTTP-клиент.
  static MediaApiClient bind(ChopperClient client) => _$MediaApiClient(client);

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

  /// Пакетная загрузка медиа по id: `GET /media/bulk?ids=1,2,3`.
  @Get(path: '/media/bulk')
  Future<Response<Map<String, dynamic>>> getMediaBulk(
    @Query('ids') String ids,
  );

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

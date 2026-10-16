import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:http/http.dart' as http;

part 'library_api_client.chopper.dart';

/// Результат создания [LibraryApiClient]: сервис и низкоуровневый
/// HTTP-клиент, который нужно закрыть через `ref.onDispose`.
typedef LibraryApiClientBundle = ({
  LibraryApiClient apiClient,
  http.Client httpClient,
});

/// Chopper-сервис библиотеки: избранное, артисты, коллекции.
///
/// Пути объявлены относительно baseUrl, который уже включает `/api`.
@ChopperApi()
abstract class LibraryApiClient extends ChopperService {
  /// Создаёт сервис вместе с его HTTP-клиентом.
  ///
  /// [httpClient] инжектируется в тестах (MockClient); по умолчанию
  /// создаётся общий [TimeoutHttpClient].
  static LibraryApiClientBundle create({
    String? baseUrl,
    List<Interceptor>? interceptors,
    http.Client? httpClient,
  }) {
    final created = createChopperClient(
      baseUrl: baseUrl ?? 'http://localhost:8080/api',
      services: [_$LibraryApiClient()],
      interceptors: interceptors,
      httpClient: httpClient,
    );
    return (
      apiClient: _$LibraryApiClient(created.client),
      httpClient: created.httpClient,
    );
  }

  /// Привязывает сервис к существующему [ChopperClient] (общему для всех
  /// сервисов приложения). В отличие от [create], не создаёт собственный
  /// HTTP-клиент.
  static LibraryApiClient bind(ChopperClient client) =>
      _$LibraryApiClient(client);

  // Favorites
  @POST(path: '/media/{id}/favorite', optionalBody: true)
  Future<Response<Map<String, dynamic>>> addFavorite(@Path('id') int id);

  @DELETE(path: '/media/{id}/favorite')
  Future<Response<Map<String, dynamic>>> removeFavorite(@Path('id') int id);

  @GET(path: '/favorites')
  Future<Response<Map<String, dynamic>>> getFavorites();

  // Artists
  @GET(path: '/artists')
  Future<Response<Map<String, dynamic>>> getArtists();

  @PUT(path: '/artists/{id}')
  Future<Response<Map<String, dynamic>>> updateArtist(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  // Collections
  @POST(path: '/collections')
  Future<Response<Map<String, dynamic>>> createCollection(
    @Body() Map<String, dynamic> body,
  );

  @GET(path: '/collections')
  Future<Response<List<dynamic>>> getCollections();

  @DELETE(path: '/collections/{id}')
  Future<Response<Map<String, dynamic>>> deleteCollection(@Path('id') int id);

  @PUT(path: '/collections/{id}')
  Future<Response<Map<String, dynamic>>> updateCollection(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @POST(path: '/collections/{id}/items')
  Future<Response<Map<String, dynamic>>> addCollectionItem(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @POST(path: '/collections/{id}/items/move')
  Future<Response<Map<String, dynamic>>> moveCollectionItem(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @DELETE(path: '/collections/{id}/items/{mediaId}')
  Future<Response<Map<String, dynamic>>> removeCollectionItem(
    @Path('id') int id,
    @Path('mediaId') int mediaId,
  );

  @GET(path: '/collections/{id}/items')
  Future<Response<List<dynamic>>> getCollectionItems(@Path('id') int id);

  @GET(path: '/collections/{id}/stats')
  Future<Response<Map<String, dynamic>>> getCollectionStats(
    @Path('id') int id,
  );

  // Trash — корзина: плоский список, восстановление, снос навсегда.
  @GET(path: '/trash')
  Future<Response<Map<String, dynamic>>> getTrash();

  @DELETE(path: '/trash')
  Future<Response<Map<String, dynamic>>> emptyTrash();

  @POST(path: '/trash/media/{id}/restore')
  Future<Response<Map<String, dynamic>>> restoreMedia(@Path('id') int id);

  @DELETE(path: '/trash/media/{id}')
  Future<Response<Map<String, dynamic>>> purgeMedia(@Path('id') int id);

  @POST(path: '/trash/collections/{id}/restore')
  Future<Response<Map<String, dynamic>>> restoreCollection(
    @Path('id') int id,
  );

  @DELETE(path: '/trash/collections/{id}')
  Future<Response<Map<String, dynamic>>> purgeCollection(@Path('id') int id);
}

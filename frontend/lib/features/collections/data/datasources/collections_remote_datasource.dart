import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/library_api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

class CollectionsRemoteDataSource {
  CollectionsRemoteDataSource(this.apiClient);

  final LibraryApiClient apiClient;

  Future<List<Collection>> getCollections() async {
    final response = await apiClient.getCollections();
    checkResponse(response, 'Failed to fetch collections');
    final body = _bodyList(response, 'Failed to fetch collections');
    final collections = <Collection>[];
    for (final json in body) {
      if (json is! Map<String, dynamic>) {
        throw const ServerException(message: 'Malformed collection item');
      }
      collections.add(Collection.fromJson(json));
    }
    return collections;
  }

  Future<Collection> createCollection({
    required String name,
    required String type,
  }) async {
    final response =
        await apiClient.createCollection({'name': name, 'type': type});
    checkResponse(response, 'Failed to create collection');
    return _collectionFromBody(response, 'Failed to create collection');
  }

  Future<Collection> updateCollection(int id, {String? name}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    final response = await apiClient.updateCollection(id, body);
    checkResponse(response, 'Failed to update collection');
    return _collectionFromBody(response, 'Failed to update collection');
  }

  Future<void> deleteCollection(int id) async {
    final response = await apiClient.deleteCollection(id);
    checkResponse(response, 'Failed to delete collection');
  }

  Future<CollectionItem> addCollectionItem(
    int collectionId,
    int mediaId,
  ) async {
    final response = await apiClient.addCollectionItem(
      collectionId,
      {'media_id': mediaId},
    );
    checkResponse(response, 'Failed to add item to collection');
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw const ServerException(
        message: 'Malformed response: Failed to add item to collection',
      );
    }
    return CollectionItem.fromJson(body);
  }

  Future<void> removeCollectionItem(int collectionId, int mediaId) async {
    final response =
        await apiClient.removeCollectionItem(collectionId, mediaId);
    checkResponse(response, 'Failed to remove item from collection');
  }

  Future<List<Media>> getCollectionItemsFull(int collectionId) async {
    final response = await apiClient.getCollectionItems(collectionId);
    checkResponse(response, 'Failed to fetch collection items');
    final body = _bodyList(response, 'Failed to fetch collection items');
    final items = <Media>[];
    for (final json in body) {
      if (json is! Map<String, dynamic>) {
        throw const ServerException(message: 'Malformed collection item');
      }
      items.add(Media.fromJson(json));
    }
    return items;
  }

  List<dynamic> _bodyList(Response<dynamic> response, String message) {
    final body = response.body;
    if (body is! List) {
      throw ServerException(message: 'Malformed response: $message');
    }
    return body;
  }

  Collection _collectionFromBody(
    Response<dynamic> response,
    String message,
  ) {
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw ServerException(message: 'Malformed response: $message');
    }
    return Collection.fromJson(body);
  }
}

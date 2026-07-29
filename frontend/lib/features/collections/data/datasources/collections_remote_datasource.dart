import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

class CollectionsRemoteDataSource {
  CollectionsRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<List<Collection>> getCollections() async {
    final response = await apiClient.getCollections();
    checkResponse(response, 'Failed to fetch collections');
    final body = response.body!;
    return body
        .map((json) => Collection.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Collection> createCollection({
    required String name,
    required String type,
  }) async {
    final response =
        await apiClient.createCollection({'name': name, 'type': type});
    checkResponse(response, 'Failed to create collection');
    return Collection.fromJson(response.body!);
  }

  Future<Collection> updateCollection(int id, {String? name}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    final response = await apiClient.updateCollection(id, body);
    checkResponse(response, 'Failed to update collection');
    return Collection.fromJson(response.body!);
  }

  Future<void> deleteCollection(int id) async {
    final response = await apiClient.deleteCollection(id);
    checkResponse(response, 'Failed to delete collection');
  }

  Future<CollectionItem> addCollectionItem(int collectionId, int mediaId) async {
    final response = await apiClient.addCollectionItem(
      collectionId,
      {'media_id': mediaId},
    );
    checkResponse(response, 'Failed to add item to collection');
    return CollectionItem.fromJson(response.body!);
  }

  Future<void> removeCollectionItem(int collectionId, int mediaId) async {
    final response =
        await apiClient.removeCollectionItem(collectionId, mediaId);
    checkResponse(response, 'Failed to remove item from collection');
  }

  Future<List<CollectionItem>> getCollectionItems(int collectionId) async {
    final response = await apiClient.getCollectionItems(collectionId);
    checkResponse(response, 'Failed to fetch collection items');
    final body = response.body!;
    return body
        .map((json) => CollectionItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<Media>> getCollectionItemsFull(int collectionId) async {
    final response = await apiClient.getCollectionItems(collectionId);
    checkResponse(response, 'Failed to fetch collection items');
    final body = response.body!;
    return body
        .map((json) => Media.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

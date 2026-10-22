import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/library_api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/collections/domain/models/bulk_items_result.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

class CollectionsRemoteDataSource {
  new(this.apiClient);

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
    int? parentId,
  }) async {
    final body = <String, dynamic>{'name': name, 'type': type};
    if (parentId != null) body['parent_id'] = parentId;
    final response = await apiClient.createCollection(body);
    checkResponse(response, 'Failed to create collection');
    return _collectionFromBody(response, 'Failed to create collection');
  }

  Future<void> deleteCollection(int id) async {
    final response = await apiClient.deleteCollection(id);
    checkResponse(response, 'Failed to delete collection');
  }

  Future<Collection> moveCollection(int id, int? parentId) async {
    final response = await apiClient.updateCollection(id, {
      'parent_id': parentId,
    });
    checkResponse(response, 'Failed to move collection');
    return _collectionFromBody(response, 'Failed to move collection');
  }

  Future<CollectionItem> moveCollectionItem(
    int sourceId,
    int targetId,
    int mediaId,
  ) async {
    final response = await apiClient.moveCollectionItem(sourceId, {
      'media_id': mediaId,
      'to_collection_id': targetId,
    });
    checkResponse(response, 'Failed to move item');
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw const ServerException(
        message: 'Malformed response: Failed to move item',
      );
    }
    return CollectionItem.fromJson(body);
  }

  Future<CollectionItem> addCollectionItem(
    int collectionId,
    int mediaId,
  ) async {
    final response = await apiClient.addCollectionItem(collectionId, {
      'media_id': mediaId,
    });
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
    final response = await apiClient.removeCollectionItem(
      collectionId,
      mediaId,
    );
    checkResponse(response, 'Failed to remove item from collection');
  }

  /// Добавляет несколько медиа в коллекцию за один запрос.
  Future<BulkItemsResult> addCollectionItemsBulk(
    int collectionId,
    List<int> mediaIds,
  ) async {
    final response = await apiClient.addCollectionItemsBulk(
      collectionId,
      {'media_ids': mediaIds},
    );
    checkResponse(response, 'Failed to add items to collection');
    return _bulkResult(response, 'Failed to add items to collection');
  }

  /// Переносит несколько элементов из своей коллекции в другую.
  Future<BulkItemsResult> moveCollectionItemsBulk(
    int sourceId,
    int targetId,
    List<int> mediaIds,
  ) async {
    final response = await apiClient.moveCollectionItemsBulk(sourceId, {
      'media_ids': mediaIds,
      'to_collection_id': targetId,
    });
    checkResponse(response, 'Failed to move items');
    return _bulkResult(response, 'Failed to move items');
  }

  /// Убирает несколько элементов из коллекции.
  Future<BulkItemsResult> removeCollectionItemsBulk(
    int collectionId,
    List<int> mediaIds,
  ) async {
    final response = await apiClient.removeCollectionItemsBulk(
      collectionId,
      {'media_ids': mediaIds},
    );
    checkResponse(response, 'Failed to remove items from collection');
    return _bulkResult(response, 'Failed to remove items from collection');
  }

  BulkItemsResult _bulkResult(
    Response<dynamic> response,
    String message,
  ) {
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw ServerException(message: 'Malformed response: $message');
    }
    return BulkItemsResult.parse(body);
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

  Collection _collectionFromBody(Response<dynamic> response, String message) {
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw ServerException(message: 'Malformed response: $message');
    }
    return Collection.fromJson(body);
  }
}

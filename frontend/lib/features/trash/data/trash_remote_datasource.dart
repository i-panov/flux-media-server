import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/library_api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Содержимое корзины: коллекции и медиа плоским списком
/// (вложенности внутри корзины нет).
class TrashContents {
  const new({required this.collections, required this.media});

  final List<Collection> collections;
  final List<Media> media;

  bool get isEmpty => collections.isEmpty && media.isEmpty;
}

/// Живые счётчики поддерева коллекции для confirm-диалога.
class CollectionStats {
  const new({required this.subcollections, required this.items});

  final int subcollections;
  final int items;
}

class TrashRemoteDataSource {
  new(this.apiClient);

  final LibraryApiClient apiClient;

  Future<TrashContents> getTrash() async {
    final response = await apiClient.getTrash();
    checkResponse(response, 'Failed to fetch trash');
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw const ServerException(message: 'Malformed response: trash');
    }
    return TrashContents(
      collections: _collectionList(body['collections']),
      media: _mediaList(body['media']),
    );
  }

  Future<void> restoreMedia(int id) async {
    final response = await apiClient.restoreMedia(id);
    checkResponse(response, 'Failed to restore media');
  }

  Future<void> purgeMedia(int id) async {
    final response = await apiClient.purgeMedia(id);
    checkResponse(response, 'Failed to permanently delete media');
  }

  Future<void> restoreCollection(int id) async {
    final response = await apiClient.restoreCollection(id);
    checkResponse(response, 'Failed to restore collection');
  }

  Future<void> purgeCollection(int id) async {
    final response = await apiClient.purgeCollection(id);
    checkResponse(response, 'Failed to permanently delete collection');
  }

  Future<void> emptyTrash() async {
    final response = await apiClient.emptyTrash();
    checkResponse(response, 'Failed to empty trash');
  }

  Future<CollectionStats> getCollectionStats(int id) async {
    final response = await apiClient.getCollectionStats(id);
    checkResponse(response, 'Failed to fetch collection stats');
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw const ServerException(message: 'Malformed response: stats');
    }
    return CollectionStats(
      subcollections: (body['subcollections'] as num?)?.toInt() ?? 0,
      items: (body['items'] as num?)?.toInt() ?? 0,
    );
  }

  List<Collection> _collectionList(Object? json) {
    if (json is! List) return const [];
    final out = <Collection>[];
    for (final item in json) {
      if (item is! Map<String, dynamic>) {
        throw const ServerException(message: 'Malformed collection item');
      }
      out.add(Collection.fromJson(item));
    }
    return out;
  }

  List<Media> _mediaList(Object? json) {
    if (json is! List) return const [];
    final out = <Media>[];
    for (final item in json) {
      if (item is! Map<String, dynamic>) {
        throw const ServerException(message: 'Malformed media item');
      }
      out.add(Media.fromJson(item));
    }
    return out;
  }
}

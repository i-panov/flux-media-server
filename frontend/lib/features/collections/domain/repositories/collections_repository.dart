import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/domain/models/bulk_items_result.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

abstract class CollectionsRepository {
  Future<Either<Failure, List<Collection>>> getCollections();
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
    int? parentId,
  });
  Future<Either<Failure, Collection>> moveCollection(int id, int? parentId);
  Future<Either<Failure, CollectionItem>> moveCollectionItem(
    int sourceId,
    int targetId,
    int mediaId,
  );
  Future<Either<Failure, void>> deleteCollection(int id);
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  );
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  );

  /// Групповые операции: сезон раскладывается по коллекции одним
  /// запросом, а не по файлу.
  Future<Either<Failure, BulkItemsResult>> addCollectionItemsBulk(
    int collectionId,
    List<int> mediaIds,
  );

  Future<Either<Failure, BulkItemsResult>> moveCollectionItemsBulk(
    int sourceId,
    int targetId,
    List<int> mediaIds,
  );

  Future<Either<Failure, BulkItemsResult>> removeCollectionItemsBulk(
    int collectionId,
    List<int> mediaIds,
  );

  /// Fetches full media items for a collection.
  /// The API returns media objects directly for collection items.
  Future<Either<Failure, List<Media>>> getCollectionItemsFull(int collectionId);
}

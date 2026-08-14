import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/features/collections/domain/usecases/add_collection_item.dart';
import 'package:flux_media_server/features/collections/domain/usecases/create_collection.dart';
import 'package:flux_media_server/features/collections/domain/usecases/delete_collection.dart';
import 'package:flux_media_server/features/collections/domain/usecases/get_collection_items_full.dart';
import 'package:flux_media_server/features/collections/domain/usecases/get_collections.dart';
import 'package:flux_media_server/features/collections/domain/usecases/remove_collection_item.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

final collectionsRemoteDataSourceProvider =
    Provider<CollectionsRemoteDataSource>((ref) {
  return CollectionsRemoteDataSource(ref.watch(libraryApiClientProvider));
});

final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) {
  return CollectionsRepositoryImpl(
    ref.watch(collectionsRemoteDataSourceProvider),
  );
});

final getCollectionsProvider = Provider<GetCollections>((ref) {
  return GetCollections(ref.watch(collectionsRepositoryProvider));
});

final createCollectionProvider = Provider<CreateCollection>((ref) {
  return CreateCollection(ref.watch(collectionsRepositoryProvider));
});

final deleteCollectionProvider = Provider<DeleteCollection>((ref) {
  return DeleteCollection(ref.watch(collectionsRepositoryProvider));
});

final addCollectionItemProvider = Provider<AddCollectionItem>((ref) {
  return AddCollectionItem(ref.watch(collectionsRepositoryProvider));
});

final removeCollectionItemProvider = Provider<RemoveCollectionItem>((ref) {
  return RemoveCollectionItem(ref.watch(collectionsRepositoryProvider));
});

final getCollectionItemsFullProvider = Provider<GetCollectionItemsFull>((ref) {
  return GetCollectionItemsFull(ref.watch(collectionsRepositoryProvider));
});

/// Fetches all user collections.
final collectionsProvider =
    FutureProvider.autoDispose<List<Collection>>((ref) async {
  final getCollections = ref.watch(getCollectionsProvider);
  final result = await getCollections(const NoParams());
  return result.fold(
    (failure) => throw Exception(failure.message),
    (collections) => collections,
  );
});

/// Fetches full media items for a specific collection (API returns
/// Media objects).
final collectionItemsFullProvider =
    FutureProvider.autoDispose.family<List<Media>, int>(
  (ref, collectionId) async {
    final getItemsFull = ref.watch(getCollectionItemsFullProvider);
    final result = await getItemsFull(collectionId);
    return result.fold(
      (failure) => throw Exception(failure.message),
      (items) => items,
    );
  },
);

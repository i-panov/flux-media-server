import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
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

/// Fetches all user collections.
final FutureProvider<List<Collection>> collectionsProvider =
    FutureProvider.autoDispose<List<Collection>>((ref) async {
      final result = await ref
          .watch(collectionsRepositoryProvider)
          .getCollections();
      return await result.fold(
        // Тип Failure сохраняется в AsyncError (не заворачивается в Exception).
        // ignore: only_throw_errors
        (failure) => throw failure,
        (collections) => collections,
      );
    });

/// Полные элементы коллекции с локальными мутациями.
///
/// [addLocal]/[removeLocal] обновляют список без refetch после
/// добавления/удаления элемента (оптимистичные апдейты).
class CollectionItemsNotifier extends AsyncNotifier<List<Media>> {
  // Riverpod 3: family-аргумент приходит через конструктор (create-функция
  // провайдера — tear-off конструктора с параметром), build() без аргументов.
  new(this.collectionId);

  final int collectionId;

  @override
  Future<List<Media>> build() async {
    final result = await ref
        .watch(collectionsRepositoryProvider)
        .getCollectionItemsFull(collectionId);
    return await result.fold(
      // Тип Failure сохраняется в AsyncError (не заворачивается в Exception).
      // ignore: only_throw_errors
      (failure) => throw failure,
      (items) => items,
    );
  }

  /// Добавляет [media] в кеш без сетевого запроса.
  void addLocal(Media media) {
    final current = state.value;
    if (current == null) return;
    if (current.any((m) => m.id == media.id)) return;
    state = AsyncValue.data([...current, media]);
  }

  /// Удаляет медиа с [mediaId] из кеша без сетевого запроса.
  void removeLocal(int mediaId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.where((m) => m.id != mediaId).toList());
  }
}

/// Fetches full media items for a specific collection (API returns
/// Media objects).
final collectionItemsFullProvider = AsyncNotifierProvider.autoDispose
    .family<CollectionItemsNotifier, List<Media>, int>(
      CollectionItemsNotifier.new,
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/features/collections/domain/usecases/add_collection_item.dart';
import 'package:flux_media_server/features/collections/domain/usecases/remove_collection_item.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

Collection _collection(int id, [String? name]) => Collection(
      id: id,
      userId: 7,
      name: name ?? 'Collection $id',
      type: MediaType.audio,
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

Media _media(int id) => Media(
      id: id,
      title: 'Media $id',
      year: 2024,
      type: MediaType.audio,
      fileSize: 100,
    );

class FakeCollectionsRepository implements CollectionsRepository {
  Future<Either<Failure, List<Collection>>> Function()? onGetCollections;
  Future<Either<Failure, CollectionItem>> Function(int, int)? onAddItem;
  Future<Either<Failure, void>> Function(int, int)? onRemoveItem;
  Future<Either<Failure, List<Media>>> Function(int)? onGetItemsFull;

  final List<(int, int)> addItemCalls = [];
  final List<(int, int)> removeItemCalls = [];

  @override
  Future<Either<Failure, List<Collection>>> getCollections() =>
      onGetCollections!();

  @override
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
  }) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, Collection>> updateCollection(
    int id, {
    String? name,
  }) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, void>> deleteCollection(int id) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  ) {
    addItemCalls.add((collectionId, mediaId));
    return onAddItem!(collectionId, mediaId);
  }

  @override
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  ) {
    removeItemCalls.add((collectionId, mediaId));
    return onRemoveItem!(collectionId, mediaId);
  }

  @override
  Future<Either<Failure, List<Media>>> getCollectionItemsFull(
    int collectionId,
  ) =>
      onGetItemsFull!(collectionId);
}

void main() {
  late ProviderContainer container;
  late FakeCollectionsRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeCollectionsRepository();
    container = ProviderContainer(
      overrides: [
        collectionsRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('collectionsProvider', () {
    test('loads the list of collections', () async {
      fakeRepo.onGetCollections =
          () async => Right([_collection(1), _collection(2, 'Second')]);

      final result = await container.read(collectionsProvider.future);

      expect(result, hasLength(2));
      expect(result.first.name, 'Collection 1');
      expect(result.last.name, 'Second');
    });

    test('throws on repository failure', () async {
      fakeRepo.onGetCollections =
          () async => const Left(ServerFailure(message: 'Boom'));

      await expectLater(
        container.read(collectionsProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('collectionItemsFullProvider', () {
    test('loads full media items for a collection', () async {
      fakeRepo.onGetItemsFull = (collectionId) async => Right(
            [_media(1), _media(2)],
          );

      final result =
          await container.read(collectionItemsFullProvider(5).future);

      expect(result, hasLength(2));
      expect(result.first.title, 'Media 1');
    });

    test('throws on repository failure', () async {
      fakeRepo.onGetItemsFull =
          (_) async => const Left(ServerFailure(message: 'Not found'));

      await expectLater(
        container.read(collectionItemsFullProvider(5).future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AddCollectionItem', () {
    test('passes collectionId and mediaId to the repository', () async {
      fakeRepo.onAddItem = (collectionId, mediaId) async => Right(
            CollectionItem(
              id: 1,
              collectionId: collectionId,
              mediaId: mediaId,
            ),
          );

      final useCase = AddCollectionItem(fakeRepo);
      final result = await useCase(
        const AddCollectionItemParams(collectionId: 3, mediaId: 42),
      );

      expect(fakeRepo.addItemCalls, [(3, 42)]);
      expect(result.isRight(), isTrue);
      final item = result.getOrElse(
        (_) => const CollectionItem(id: 0),
      );
      expect(item.collectionId, 3);
      expect(item.mediaId, 42);
    });

    test('propagates repository failure', () async {
      fakeRepo.onAddItem =
          (_, __) async => const Left(ServerFailure(message: 'Conflict'));

      final useCase = AddCollectionItem(fakeRepo);
      final result = await useCase(
        const AddCollectionItemParams(collectionId: 3, mediaId: 42),
      );

      expect(result.isLeft(), isTrue);
      expect(result.fold((l) => l.message, (_) => ''), 'Conflict');
    });
  });

  group('RemoveCollectionItem', () {
    test('passes collectionId and mediaId to the repository', () async {
      fakeRepo.onRemoveItem = (_, __) async => const Right(null);

      final useCase = RemoveCollectionItem(fakeRepo);
      final result = await useCase(
        const RemoveCollectionItemParams(collectionId: 3, mediaId: 42),
      );

      expect(fakeRepo.removeItemCalls, [(3, 42)]);
      expect(result.isRight(), isTrue);
    });

    test('propagates repository failure', () async {
      fakeRepo.onRemoveItem =
          (_, __) async => const Left(ServerFailure(message: 'Not found'));

      final useCase = RemoveCollectionItem(fakeRepo);
      final result = await useCase(
        const RemoveCollectionItemParams(collectionId: 3, mediaId: 42),
      );

      expect(result.isLeft(), isTrue);
    });
  });
}

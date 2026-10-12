import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/fake_repositories.dart';

void main() {
  late ProviderContainer container;
  late FakeCollectionsRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeCollectionsRepository();
    container = ProviderContainer(
      overrides: [collectionsRepositoryProvider.overrideWithValue(fakeRepo)],
      // Riverpod 3 ретраит упавшие build-и по умолчанию: отключаем,
      // чтобы «throws on failure»-тесты видели ошибку сразу.
      retry: (_, _) => null,
    );
  });

  tearDown(() => container.dispose());

  group('collectionsProvider', () {
    test('loads the list of collections', () async {
      fakeRepo.onGetCollections = () async =>
          Right([collection(1), collection(2, 'Second')]);

      final result = await container.read(collectionsProvider.future);

      expect(result, hasLength(2));
      expect(result.first.name, 'Collection 1');
      expect(result.last.name, 'Second');
    });

    test('throws on repository failure', () async {
      fakeRepo.onGetCollections = () async =>
          const Left(ServerFailure(message: 'Boom'));

      // Тип Failure сохраняется — не заворачивается в Exception.
      await expectLater(
        container.read(collectionsProvider.future),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('collectionItemsFullProvider', () {
    test('loads full media items for a collection', () async {
      fakeRepo.onGetItemsFull = (collectionId) async =>
          Right([media(1), media(2)]);

      final result = await container.read(
        collectionItemsFullProvider(5).future,
      );

      expect(result, hasLength(2));
      expect(result.first.title, 'Media 1');
    });

    test('throws on repository failure', () async {
      fakeRepo.onGetItemsFull = (_) async =>
          const Left(ServerFailure(message: 'Not found'));

      // Riverpod 3: без подписки autoDispose-провайдер диспоузится до
      // завершения future — держим его живым на время проверки.
      final sub = container.listen(collectionItemsFullProvider(5), (_, _) {});
      await expectLater(
        container.read(collectionItemsFullProvider(5).future),
        throwsA(isA<ServerFailure>()),
      );
      sub.close();
    });

    test('removeLocal removes an item without a refetch', () async {
      fakeRepo.onGetItemsFull = (collectionId) async =>
          Right([media(1), media(2)]);
      final sub = container.listen(collectionItemsFullProvider(5), (_, _) {});
      addTearDown(sub.close);
      await container.read(collectionItemsFullProvider(5).future);

      container.read(collectionItemsFullProvider(5).notifier).removeLocal(1);

      expect(fakeRepo.getItemsFullCalls, 1);
      final items = container.read(collectionItemsFullProvider(5)).value;
      expect(items?.map((m) => m.id), [2]);
    });

    test('addLocal appends an item without a refetch', () async {
      fakeRepo.onGetItemsFull = (collectionId) async => Right([media(1)]);
      final sub = container.listen(collectionItemsFullProvider(5), (_, _) {});
      addTearDown(sub.close);
      await container.read(collectionItemsFullProvider(5).future);

      container
          .read(collectionItemsFullProvider(5).notifier)
          .addLocal(media(3));

      expect(fakeRepo.getItemsFullCalls, 1);
      final items = container.read(collectionItemsFullProvider(5)).value;
      expect(items?.map((m) => m.id), [1, 3]);
    });

    test('addLocal dedupes by media id', () async {
      fakeRepo.onGetItemsFull = (collectionId) async => Right([media(1)]);
      final sub = container.listen(collectionItemsFullProvider(5), (_, _) {});
      addTearDown(sub.close);
      await container.read(collectionItemsFullProvider(5).future);

      container
          .read(collectionItemsFullProvider(5).notifier)
          .addLocal(media(1));

      final items = container.read(collectionItemsFullProvider(5)).value;
      expect(items, hasLength(1));
    });

    test('invalidate refetches the collection items', () async {
      fakeRepo.onGetItemsFull = (collectionId) async => Right([media(1)]);
      final sub = container.listen(collectionItemsFullProvider(5), (_, _) {});
      addTearDown(sub.close);
      await container.read(collectionItemsFullProvider(5).future);

      container.invalidate(collectionItemsFullProvider(5));
      await container.read(collectionItemsFullProvider(5).future);

      expect(fakeRepo.getItemsFullCalls, 2);
    });
  });
}

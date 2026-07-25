# Frontend API Layer + Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Flutter API endpoints, freezed models, datasources, repositories, and Riverpod providers for favorites, collections, and lyrics — the data layer foundation for the UI redesign.

**Architecture:** Follows existing patterns: Chopper API definitions in `api_client.dart`, freezed models in `shared/models/`, datasources in `features/<feature>/data/datasources/`, repository interfaces in `features/<feature>/domain/repositories/`, repository implementations in `features/<feature>/data/repositories/`, providers in `features/<feature>/presentation/providers/`. Uses fpdart `Either<Failure, T>` for error handling, `checkResponse()` for HTTP status checking.

**Tech Stack:** Flutter, Chopper, freezed, json_serializable, fpdart, flutter_riverpod

---

## File Structure

### New files

| File | Responsibility |
|------|----------------|
| `frontend/lib/shared/models/favorite.dart` | Favorite freezed model |
| `frontend/lib/shared/models/collection.dart` | Collection + CollectionItem freezed models |
| `frontend/lib/shared/models/lyrics.dart` | Lyrics freezed model |
| `frontend/lib/features/favorites/data/datasources/favorites_remote_datasource.dart` | Favorites API calls |
| `frontend/lib/features/favorites/data/repositories/favorites_repository_impl.dart` | Favorites repository impl |
| `frontend/lib/features/favorites/domain/repositories/favorites_repository.dart` | Favorites repository interface |
| `frontend/lib/features/favorites/domain/usecases/add_favorite.dart` | Add favorite usecase |
| `frontend/lib/features/favorites/domain/usecases/remove_favorite.dart` | Remove favorite usecase |
| `frontend/lib/features/favorites/domain/usecases/get_favorites.dart` | Get favorites usecase |
| `frontend/lib/features/favorites/presentation/providers/favorites_provider.dart` | Favorites Riverpod providers |
| `frontend/lib/features/collections/data/datasources/collections_remote_datasource.dart` | Collections API calls |
| `frontend/lib/features/collections/data/repositories/collections_repository_impl.dart` | Collections repository impl |
| `frontend/lib/features/collections/domain/repositories/collections_repository.dart` | Collections repository interface |
| `frontend/lib/features/collections/domain/usecases/create_collection.dart` | Create collection usecase |
| `frontend/lib/features/collections/domain/usecases/get_collections.dart` | Get collections usecase |
| `frontend/lib/features/collections/domain/usecases/delete_collection.dart` | Delete collection usecase |
| `frontend/lib/features/collections/domain/usecases/add_collection_item.dart` | Add item to collection |
| `frontend/lib/features/collections/domain/usecases/remove_collection_item.dart` | Remove item from collection |
| `frontend/lib/features/collections/domain/usecases/get_collection_items.dart` | Get collection items |
| `frontend/lib/features/collections/presentation/providers/collections_provider.dart` | Collections Riverpod providers |
| `frontend/lib/features/lyrics/data/datasources/lyrics_remote_datasource.dart` | Lyrics API calls |
| `frontend/lib/features/lyrics/data/repositories/lyrics_repository_impl.dart` | Lyrics repository impl |
| `frontend/lib/features/lyrics/domain/repositories/lyrics_repository.dart` | Lyrics repository interface |
| `frontend/lib/features/lyrics/domain/usecases/get_lyrics.dart` | Get lyrics usecase |
| `frontend/lib/features/lyrics/domain/usecases/upsert_lyrics.dart` | Upsert lyrics usecase |
| `frontend/lib/features/lyrics/presentation/providers/lyrics_provider.dart` | Lyrics Riverpod providers |

### Modified files

| File | Changes |
|------|---------|
| `frontend/lib/core/network/api_client.dart` | Add Chopper API method definitions for favorites, collections, lyrics |
| `frontend/lib/core/usecases/usecase.dart` | No changes (already generic) |

---

## Task 1: Favorite Model

**Files:**
- Create: `frontend/lib/shared/models/favorite.dart`

- [ ] **Step 1: Create the model**

Create `frontend/lib/shared/models/favorite.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'favorite.freezed.dart';
part 'favorite.g.dart';

@freezed
class Favorite with _$Favorite {
  const factory Favorite({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    required String type, // video, audio, artist
    @JsonKey(name: 'media_id') int? mediaId,
    @JsonKey(name: 'artist_name') String? artistName,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Favorite;

  factory Favorite.fromJson(Map<String, dynamic> json) =>
      _$FavoriteFromJson(json);
}
```

- [ ] **Step 2: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: `favorite.freezed.dart` and `favorite.g.dart` generated successfully

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/shared/models/favorite.dart frontend/lib/shared/models/favorite.freezed.dart frontend/lib/shared/models/favorite.g.dart
git commit -m "feat: add Favorite model"
```

---

## Task 2: Collection + CollectionItem Models

**Files:**
- Create: `frontend/lib/shared/models/collection.dart`

- [ ] **Step 1: Create the models**

Create `frontend/lib/shared/models/collection.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'collection.freezed.dart';
part 'collection.g.dart';

@freezed
class Collection with _$Collection {
  const factory Collection({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    required String name,
    required String type,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Collection;

  factory Collection.fromJson(Map<String, dynamic> json) =>
      _$CollectionFromJson(json);
}

@freezed
class CollectionItem with _$CollectionItem {
  const factory CollectionItem({
    required int id,
    @JsonKey(name: 'collection_id') required int collectionId,
    @JsonKey(name: 'media_id') required int mediaId,
    @JsonKey(name: 'added_at') required DateTime addedAt,
  }) = _CollectionItem;

  factory CollectionItem.fromJson(Map<String, dynamic> json) =>
      _$CollectionItemFromJson(json);
}
```

- [ ] **Step 2: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: Generated files created

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/shared/models/collection.dart frontend/lib/shared/models/collection.freezed.dart frontend/lib/shared/models/collection.g.dart
git commit -m "feat: add Collection and CollectionItem models"
```

---

## Task 3: Lyrics Model

**Files:**
- Create: `frontend/lib/shared/models/lyrics.dart`

- [ ] **Step 1: Create the model**

Create `frontend/lib/shared/models/lyrics.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'lyrics.freezed.dart';
part 'lyrics.g.dart';

@freezed
class Lyrics with _$Lyrics {
  const factory Lyrics({
    required int id,
    @JsonKey(name: 'media_id') required int mediaId,
    @JsonKey(name: 'lyrics_text') @Default('') String lyricsText,
    @JsonKey(name: 'translation') @Default('') String translation,
    @JsonKey(name: 'sync_data') @Default('') String syncData,
    required String source,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Lyrics;

  factory Lyrics.fromJson(Map<String, dynamic> json) =>
      _$LyricsFromJson(json);
}
```

- [ ] **Step 2: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: Generated files created

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/shared/models/lyrics.dart frontend/lib/shared/models/lyrics.freezed.dart frontend/lib/shared/models/lyrics.g.dart
git commit -m "feat: add Lyrics model"
```

---

## Task 4: API Client — Add Endpoint Definitions

**Files:**
- Modify: `frontend/lib/core/network/api_client.dart`

- [ ] **Step 1: Add favorites, collections, and lyrics endpoints**

In `frontend/lib/core/network/api_client.dart`, add these method definitions before the closing `}` of the class:

```dart
  // Favorites
  @Post(path: '/media/{id}/favorite', optionalBody: true)
  Future<Response<Map<String, dynamic>>> addFavorite(@Path('id') int id);

  @Delete(path: '/media/{id}/favorite')
  Future<Response<Map<String, dynamic>>> removeFavorite(@Path('id') int id);

  @Get(path: '/favorites')
  Future<Response<List<dynamic>>> getFavorites({
    @Query('type') String? type,
  });

  @Post(path: '/favorites/artist')
  Future<Response<Map<String, dynamic>>> addArtistFavorite(
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/favorites/artist')
  Future<Response<Map<String, dynamic>>> removeArtistFavorite(
    @Query('artist') String artist,
  );

  // Collections
  @Post(path: '/collections')
  Future<Response<Map<String, dynamic>>> createCollection(
    @Body() Map<String, dynamic> body,
  );

  @Get(path: '/collections')
  Future<Response<List<dynamic>>> getCollections();

  @Put(path: '/collections/{id}')
  Future<Response<Map<String, dynamic>>> updateCollection(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/collections/{id}')
  Future<Response<Map<String, dynamic>>> deleteCollection(@Path('id') int id);

  @Post(path: '/collections/{id}/items')
  Future<Response<Map<String, dynamic>>> addCollectionItem(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );

  @Delete(path: '/collections/{id}/items/{mediaId}')
  Future<Response<Map<String, dynamic>>> removeCollectionItem(
    @Path('id') int id,
    @Path('mediaId') int mediaId,
  );

  @Get(path: '/collections/{id}/items')
  Future<Response<List<dynamic>>> getCollectionItems(@Path('id') int id);

  // Lyrics
  @Get(path: '/media/{id}/lyrics')
  Future<Response<Map<String, dynamic>>> getLyrics(@Path('id') int id);

  @Put(path: '/media/{id}/lyrics')
  Future<Response<Map<String, dynamic>>> upsertLyrics(
    @Path('id') int id,
    @Body() Map<String, dynamic> body,
  );
```

- [ ] **Step 2: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: `api_client.chopper.dart` regenerated with new methods

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && flutter analyze lib/core/network/api_client.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/core/network/api_client.dart frontend/lib/core/network/api_client.chopper.dart
git commit -m "feat: add favorites, collections, lyrics API endpoints"
```

---

## Task 5: Favorites Feature — Data Layer

**Files:**
- Create: `frontend/lib/features/favorites/data/datasources/favorites_remote_datasource.dart`
- Create: `frontend/lib/features/favorites/domain/repositories/favorites_repository.dart`
- Create: `frontend/lib/features/favorites/data/repositories/favorites_repository_impl.dart`

- [ ] **Step 1: Create the datasource**

Create `frontend/lib/features/favorites/data/datasources/favorites_remote_datasource.dart`:

```dart
import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRemoteDataSource {
  FavoritesRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<List<Favorite>> getFavorites({String? type}) async {
    final response = await apiClient.getFavorites(type: type);
    checkResponse(response, 'Failed to fetch favorites');
    final body = response.body!;
    return body
        .map((json) => Favorite.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Favorite> addFavorite(int mediaId) async {
    final response = await apiClient.addFavorite(mediaId);
    checkResponse(response, 'Failed to add favorite');
    return Favorite.fromJson(response.body!);
  }

  Future<void> removeFavorite(int mediaId) async {
    final response = await apiClient.removeFavorite(mediaId);
    checkResponse(response, 'Failed to remove favorite');
  }

  Future<Favorite> addArtistFavorite(String artistName) async {
    final response =
        await apiClient.addArtistFavorite({'artist': artistName});
    checkResponse(response, 'Failed to add artist favorite');
    return Favorite.fromJson(response.body!);
  }

  Future<void> removeArtistFavorite(String artistName) async {
    final response = await apiClient.removeArtistFavorite(artistName);
    checkResponse(response, 'Failed to remove artist favorite');
  }
}
```

- [ ] **Step 2: Create the repository interface**

Create `frontend/lib/features/favorites/domain/repositories/favorites_repository.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

abstract class FavoritesRepository {
  Future<Either<Failure, List<Favorite>>> getFavorites({String? type});
  Future<Either<Failure, Favorite>> addFavorite(int mediaId);
  Future<Either<Failure, void>> removeFavorite(int mediaId);
  Future<Either<Failure, Favorite>> addArtistFavorite(String artistName);
  Future<Either<Failure, void>> removeArtistFavorite(String artistName);
}
```

- [ ] **Step 3: Create the repository implementation**

Create `frontend/lib/features/favorites/data/repositories/favorites_repository_impl.dart`:

```dart
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/data/datasources/favorites_remote_datasource.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  FavoritesRepositoryImpl(this.remoteDataSource);

  final FavoritesRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<Favorite>>> getFavorites({String? type}) async {
    try {
      final favorites = await remoteDataSource.getFavorites(type: type);
      return Right(favorites);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Favorite>> addFavorite(int mediaId) async {
    try {
      final favorite = await remoteDataSource.addFavorite(mediaId);
      return Right(favorite);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> removeFavorite(int mediaId) async {
    try {
      await remoteDataSource.removeFavorite(mediaId);
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Favorite>> addArtistFavorite(String artistName) async {
    try {
      final favorite = await remoteDataSource.addArtistFavorite(artistName);
      return Right(favorite);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> removeArtistFavorite(String artistName) async {
    try {
      await remoteDataSource.removeArtistFavorite(artistName);
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd frontend && flutter analyze lib/features/favorites/`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/favorites/
git commit -m "feat: add favorites data layer (datasource, repository)"
```

---

## Task 6: Favorites Feature — Domain + Providers

**Files:**
- Create: `frontend/lib/features/favorites/domain/usecases/add_favorite.dart`
- Create: `frontend/lib/features/favorites/domain/usecases/remove_favorite.dart`
- Create: `frontend/lib/features/favorites/domain/usecases/get_favorites.dart`
- Create: `frontend/lib/features/favorites/presentation/providers/favorites_provider.dart`

- [ ] **Step 1: Create use cases**

Create `frontend/lib/features/favorites/domain/usecases/add_favorite.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class AddFavorite extends UseCase<Either<Failure, Favorite>, int> {
  AddFavorite(this.repository);
  final FavoritesRepository repository;

  @override
  Future<Either<Failure, Favorite>> call(int mediaId) {
    return repository.addFavorite(mediaId);
  }
}
```

Create `frontend/lib/features/favorites/domain/usecases/remove_favorite.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';

class RemoveFavorite extends UseCase<Either<Failure, void>, int> {
  RemoveFavorite(this.repository);
  final FavoritesRepository repository;

  @override
  Future<Either<Failure, void>> call(int mediaId) {
    return repository.removeFavorite(mediaId);
  }
}
```

Create `frontend/lib/features/favorites/domain/usecases/get_favorites.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

class GetFavoritesParams {
  const GetFavoritesParams({this.type});
  final String? type;
}

class GetFavorites
    extends UseCase<Either<Failure, List<Favorite>>, GetFavoritesParams> {
  GetFavorites(this.repository);
  final FavoritesRepository repository;

  @override
  Future<Either<Failure, List<Favorite>>> call(GetFavoritesParams params) {
    return repository.getFavorites(type: params.type);
  }
}
```

- [ ] **Step 2: Create providers**

Create `frontend/lib/features/favorites/presentation/providers/favorites_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/favorites/data/datasources/favorites_remote_datasource.dart';
import 'package:flux_media_server/features/favorites/data/repositories/favorites_repository_impl.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/features/favorites/domain/usecases/add_favorite.dart';
import 'package:flux_media_server/features/favorites/domain/usecases/get_favorites.dart';
import 'package:flux_media_server/features/favorites/domain/usecases/remove_favorite.dart';
import 'package:flux_media_server/shared/models/favorite.dart';

final favoritesRemoteDataSourceProvider =
    Provider<FavoritesRemoteDataSource>((ref) {
  return FavoritesRemoteDataSource(ref.watch(apiClientProvider));
});

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepositoryImpl(
    ref.watch(favoritesRemoteDataSourceProvider),
  );
});

final getFavoritesProvider = Provider<GetFavorites>((ref) {
  return GetFavorites(ref.watch(favoritesRepositoryProvider));
});

final addFavoriteProvider = Provider<AddFavorite>((ref) {
  return AddFavorite(ref.watch(favoritesRepositoryProvider));
});

final removeFavoriteProvider = Provider<RemoveFavorite>((ref) {
  return RemoveFavorite(ref.watch(favoritesRepositoryProvider));
});

/// Fetches favorites, optionally filtered by type.
final favoritesProvider =
    FutureProvider.autoDispose.family<List<Favorite>, String?>((ref, type) async {
  final getFavorites = ref.watch(getFavoritesProvider);
  final result = await getFavorites(GetFavoritesParams(type: type));
  return result.fold(
    (failure) => throw Exception(failure.message),
    (favorites) => favorites,
  );
});

/// Tracks favorite media IDs for quick lookup.
final favoriteMediaIdsProvider =
    FutureProvider.autoDispose.family<Set<int>, String>((ref, type) async {
  final favorites = await ref.watch(favoritesProvider(type));
  return favorites
      .where((f) => f.mediaId != null)
      .map((f) => f.mediaId!)
      .toSet();
});
```

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && flutter analyze lib/features/favorites/`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/features/favorites/
git commit -m "feat: add favorites usecases and providers"
```

---

## Task 7: Collections Feature — Data Layer

**Files:**
- Create: `frontend/lib/features/collections/data/datasources/collections_remote_datasource.dart`
- Create: `frontend/lib/features/collections/domain/repositories/collections_repository.dart`
- Create: `frontend/lib/features/collections/data/repositories/collections_repository_impl.dart`

- [ ] **Step 1: Create the datasource**

Create `frontend/lib/features/collections/data/datasources/collections_remote_datasource.dart`:

```dart
import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/collection.dart';

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

  Future<Collection> createCollection({required String name, required String type}) async {
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
}
```

- [ ] **Step 2: Create the repository interface**

Create `frontend/lib/features/collections/domain/repositories/collections_repository.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/collection.dart';

abstract class CollectionsRepository {
  Future<Either<Failure, List<Collection>>> getCollections();
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
  });
  Future<Either<Failure, Collection>> updateCollection(int id, {String? name});
  Future<Either<Failure, void>> deleteCollection(int id);
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  );
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  );
  Future<Either<Failure, List<CollectionItem>>> getCollectionItems(
    int collectionId,
  );
}
```

- [ ] **Step 3: Create the repository implementation**

Create `frontend/lib/features/collections/data/repositories/collections_repository_impl.dart`:

```dart
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class CollectionsRepositoryImpl implements CollectionsRepository {
  CollectionsRepositoryImpl(this.remoteDataSource);

  final CollectionsRemoteDataSource remoteDataSource;

  Future<Either<Failure, T>> _wrap<T>(Future<T> Function() fn) async {
    try {
      return Right(await fn());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, List<Collection>>> getCollections() =>
      _wrap(() => remoteDataSource.getCollections());

  @override
  Future<Either<Failure, Collection>> createCollection({
    required String name,
    required String type,
  }) =>
      _wrap(() => remoteDataSource.createCollection(name: name, type: type));

  @override
  Future<Either<Failure, Collection>> updateCollection(int id, {String? name}) =>
      _wrap(() => remoteDataSource.updateCollection(id, name: name));

  @override
  Future<Either<Failure, void>> deleteCollection(int id) =>
      _wrap(() => remoteDataSource.deleteCollection(id));

  @override
  Future<Either<Failure, CollectionItem>> addCollectionItem(
    int collectionId,
    int mediaId,
  ) =>
      _wrap(() => remoteDataSource.addCollectionItem(collectionId, mediaId));

  @override
  Future<Either<Failure, void>> removeCollectionItem(
    int collectionId,
    int mediaId,
  ) =>
      _wrap(() => remoteDataSource.removeCollectionItem(collectionId, mediaId));

  @override
  Future<Either<Failure, List<CollectionItem>>> getCollectionItems(
    int collectionId,
  ) =>
      _wrap(() => remoteDataSource.getCollectionItems(collectionId));
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd frontend && flutter analyze lib/features/collections/`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/collections/
git commit -m "feat: add collections data layer (datasource, repository)"
```

---

## Task 8: Collections Feature — Domain + Providers

**Files:**
- Create: `frontend/lib/features/collections/domain/usecases/create_collection.dart`
- Create: `frontend/lib/features/collections/domain/usecases/get_collections.dart`
- Create: `frontend/lib/features/collections/domain/usecases/delete_collection.dart`
- Create: `frontend/lib/features/collections/domain/usecases/add_collection_item.dart`
- Create: `frontend/lib/features/collections/domain/usecases/remove_collection_item.dart`
- Create: `frontend/lib/features/collections/domain/usecases/get_collection_items.dart`
- Create: `frontend/lib/features/collections/presentation/providers/collections_provider.dart`

- [ ] **Step 1: Create use cases**

Create `frontend/lib/features/collections/domain/usecases/create_collection.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class CreateCollectionParams {
  const CreateCollectionParams({required this.name, required this.type});
  final String name;
  final String type;
}

class CreateCollection
    extends UseCase<Either<Failure, Collection>, CreateCollectionParams> {
  CreateCollection(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, Collection>> call(CreateCollectionParams params) {
    return repository.createCollection(name: params.name, type: params.type);
  }
}
```

Create `frontend/lib/features/collections/domain/usecases/get_collections.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class GetCollections
    extends UseCase<Either<Failure, List<Collection>>, NoParams> {
  GetCollections(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, List<Collection>>> call(NoParams params) {
    return repository.getCollections();
  }
}
```

Create `frontend/lib/features/collections/domain/usecases/delete_collection.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';

class DeleteCollection extends UseCase<Either<Failure, void>, int> {
  DeleteCollection(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, void>> call(int id) {
    return repository.deleteCollection(id);
  }
}
```

Create `frontend/lib/features/collections/domain/usecases/add_collection_item.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class AddCollectionItemParams {
  const AddCollectionItemParams({
    required this.collectionId,
    required this.mediaId,
  });
  final int collectionId;
  final int mediaId;
}

class AddCollectionItem
    extends UseCase<Either<Failure, CollectionItem>, AddCollectionItemParams> {
  AddCollectionItem(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, CollectionItem>> call(AddCollectionItemParams params) {
    return repository.addCollectionItem(params.collectionId, params.mediaId);
  }
}
```

Create `frontend/lib/features/collections/domain/usecases/remove_collection_item.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';

class RemoveCollectionItemParams {
  const RemoveCollectionItemParams({
    required this.collectionId,
    required this.mediaId,
  });
  final int collectionId;
  final int mediaId;
}

class RemoveCollectionItem
    extends UseCase<Either<Failure, void>, RemoveCollectionItemParams> {
  RemoveCollectionItem(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, void>> call(RemoveCollectionItemParams params) {
    return repository.removeCollectionItem(params.collectionId, params.mediaId);
  }
}
```

Create `frontend/lib/features/collections/domain/usecases/get_collection_items.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';

class GetCollectionItems
    extends UseCase<Either<Failure, List<CollectionItem>>, int> {
  GetCollectionItems(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, List<CollectionItem>>> call(int collectionId) {
    return repository.getCollectionItems(collectionId);
  }
}
```

- [ ] **Step 2: Create providers**

Create `frontend/lib/features/collections/presentation/providers/collections_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/collections/data/datasources/collections_remote_datasource.dart';
import 'package:flux_media_server/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/features/collections/domain/usecases/add_collection_item.dart';
import 'package:flux_media_server/features/collections/domain/usecases/create_collection.dart';
import 'package:flux_media_server/features/collections/domain/usecases/delete_collection.dart';
import 'package:flux_media_server/features/collections/domain/usecases/get_collection_items.dart';
import 'package:flux_media_server/features/collections/domain/usecases/get_collections.dart';
import 'package:flux_media_server/features/collections/domain/usecases/remove_collection_item.dart';
import 'package:flux_media_server/shared/models/collection.dart';

final collectionsRemoteDataSourceProvider =
    Provider<CollectionsRemoteDataSource>((ref) {
  return CollectionsRemoteDataSource(ref.watch(apiClientProvider));
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

final getCollectionItemsProvider = Provider<GetCollectionItems>((ref) {
  return GetCollectionItems(ref.watch(collectionsRepositoryProvider));
});

/// Fetches all user collections.
final collectionsProvider =
    FutureProvider.autoDispose<List<Collection>>((ref) async {
  final getCollections = ref.watch(getCollectionsProvider);
  final result = await getCollections(NoParams());
  return result.fold(
    (failure) => throw Exception(failure.message),
    (collections) => collections,
  );
});

/// Fetches items for a specific collection.
final collectionItemsProvider =
    FutureProvider.autoDispose.family<List<CollectionItem>, int>(
  (ref, collectionId) async {
    final getItems = ref.watch(getCollectionItemsProvider);
    final result = await getItems(collectionId);
    return result.fold(
      (failure) => throw Exception(failure.message),
      (items) => items,
    );
  },
);
```

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && flutter analyze lib/features/collections/`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/features/collections/
git commit -m "feat: add collections usecases and providers"
```

---

## Task 9: Lyrics Feature — Full Stack

**Files:**
- Create: `frontend/lib/features/lyrics/data/datasources/lyrics_remote_datasource.dart`
- Create: `frontend/lib/features/lyrics/domain/repositories/lyrics_repository.dart`
- Create: `frontend/lib/features/lyrics/data/repositories/lyrics_repository_impl.dart`
- Create: `frontend/lib/features/lyrics/domain/usecases/get_lyrics.dart`
- Create: `frontend/lib/features/lyrics/domain/usecases/upsert_lyrics.dart`
- Create: `frontend/lib/features/lyrics/presentation/providers/lyrics_provider.dart`

- [ ] **Step 1: Create the datasource**

Create `frontend/lib/features/lyrics/data/datasources/lyrics_remote_datasource.dart`:

```dart
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class LyricsRemoteDataSource {
  LyricsRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<Lyrics?> getLyrics(int mediaId) async {
    final response = await apiClient.getLyrics(mediaId);
    if (response.statusCode == 404) {
      return null;
    }
    checkResponse(response, 'Failed to fetch lyrics');
    return Lyrics.fromJson(response.body!);
  }

  Future<Lyrics> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    String? translation,
    String? syncData,
    required String source,
  }) async {
    final response = await apiClient.upsertLyrics(mediaId, {
      'lyrics_text': lyricsText,
      'translation': translation ?? '',
      'sync_data': syncData ?? '',
      'source': source,
    });
    checkResponse(response, 'Failed to save lyrics');
    return Lyrics.fromJson(response.body!);
  }
}
```

- [ ] **Step 2: Create the repository interface**

Create `frontend/lib/features/lyrics/domain/repositories/lyrics_repository.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

abstract class LyricsRepository {
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId);
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    String? translation,
    String? syncData,
    required String source,
  });
}
```

- [ ] **Step 3: Create the repository implementation**

Create `frontend/lib/features/lyrics/data/repositories/lyrics_repository_impl.dart`:

```dart
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/lyrics/data/datasources/lyrics_remote_datasource.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  LyricsRepositoryImpl(this.remoteDataSource);

  final LyricsRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId) async {
    try {
      final lyrics = await remoteDataSource.getLyrics(mediaId);
      return Right(lyrics);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    String? translation,
    String? syncData,
    required String source,
  }) async {
    try {
      final lyrics = await remoteDataSource.upsertLyrics(
        mediaId,
        lyricsText: lyricsText,
        translation: translation,
        syncData: syncData,
        source: source,
      );
      return Right(lyrics);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }
}
```

- [ ] **Step 4: Create use cases**

Create `frontend/lib/features/lyrics/domain/usecases/get_lyrics.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class GetLyrics extends UseCase<Either<Failure, Lyrics?>, int> {
  GetLyrics(this.repository);
  final LyricsRepository repository;

  @override
  Future<Either<Failure, Lyrics?>> call(int mediaId) {
    return repository.getLyrics(mediaId);
  }
}
```

Create `frontend/lib/features/lyrics/domain/usecases/upsert_lyrics.dart`:

```dart
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class UpsertLyricsParams {
  const UpsertLyricsParams({
    required this.mediaId,
    required this.lyricsText,
    this.translation,
    this.syncData,
    required this.source,
  });
  final int mediaId;
  final String lyricsText;
  final String? translation;
  final String? syncData;
  final String source;
}

class UpsertLyrics
    extends UseCase<Either<Failure, Lyrics>, UpsertLyricsParams> {
  UpsertLyrics(this.repository);
  final LyricsRepository repository;

  @override
  Future<Either<Failure, Lyrics>> call(UpsertLyricsParams params) {
    return repository.upsertLyrics(
      params.mediaId,
      lyricsText: params.lyricsText,
      translation: params.translation,
      syncData: params.syncData,
      source: params.source,
    );
  }
}
```

- [ ] **Step 5: Create providers**

Create `frontend/lib/features/lyrics/presentation/providers/lyrics_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/lyrics/data/datasources/lyrics_remote_datasource.dart';
import 'package:flux_media_server/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/get_lyrics.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/upsert_lyrics.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

final lyricsRemoteDataSourceProvider = Provider<LyricsRemoteDataSource>((ref) {
  return LyricsRemoteDataSource(ref.watch(apiClientProvider));
});

final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  return LyricsRepositoryImpl(ref.watch(lyricsRemoteDataSourceProvider));
});

final getLyricsProvider = Provider<GetLyrics>((ref) {
  return GetLyrics(ref.watch(lyricsRepositoryProvider));
});

final upsertLyricsProvider = Provider<UpsertLyrics>((ref) {
  return UpsertLyrics(ref.watch(lyricsRepositoryProvider));
});

/// Fetches lyrics for a media item. Returns null if no lyrics exist.
final lyricsProvider =
    FutureProvider.autoDispose.family<Lyrics?, int>((ref, mediaId) async {
  final getLyrics = ref.watch(getLyricsProvider);
  final result = await getLyrics(mediaId);
  return result.fold(
    (failure) => throw Exception(failure.message),
    (lyrics) => lyrics,
  );
});
```

- [ ] **Step 6: Verify it compiles**

Run: `cd frontend && flutter analyze lib/features/lyrics/`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/features/lyrics/
git commit -m "feat: add lyrics full stack (datasource, repository, usecases, providers)"
```

---

## Task 10: Full Build Verification

- [ ] **Step 1: Run build_runner for all generated files**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: All generated files created successfully

- [ ] **Step 2: Run analyzer on entire project**

Run: `cd frontend && flutter analyze`
Expected: No errors in new files

- [ ] **Step 3: Verify app still builds**

Run: `cd frontend && flutter build apk --debug --no-tree-shake-icons` (or `flutter build web --debug` if not on Android)
Expected: Build succeeds

- [ ] **Step 4: Commit any remaining generated files**

```bash
git add frontend/
git commit -m "chore: regenerate build_runner output"
```

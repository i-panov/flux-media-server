import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_cache_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

Favorite favorite({
  int id = 1,
  int? mediaId,
  int? artistId,
}) =>
    Favorite(
      id: id,
      userId: 7,
      createdAt: DateTime.utc(2024),
      mediaId: mediaId,
      artistId: artistId,
    );

Collection collection(int id, [String? name]) => Collection(
      id: id,
      userId: 7,
      name: name ?? 'Collection $id',
      type: MediaType.audio,
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

Media media(int id) => Media(
      id: id,
      title: 'Media $id',
      year: 2024,
      type: MediaType.audio,
      fileSize: 100,
    );

Lyrics fakeLyrics([int mediaId = 5]) => Lyrics(
      id: 1,
      mediaId: mediaId,
      source: 'musixmatch',
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
      lyricsText: 'La la la',
      translation: 'Ля-ля-ля',
    );

class FakeFavoritesRepository implements FavoritesRepository {
  Future<Either<Failure, List<Favorite>>> Function()? onGetFavorites;
  Future<Either<Failure, Favorite>> Function(int)? onAddFavorite;
  Future<Either<Failure, void>> Function(int)? onRemoveFavorite;

  int getFavoritesCalls = 0;
  final List<int> addFavoriteCalls = [];
  final List<int> removeFavoriteCalls = [];

  @override
  Future<Either<Failure, List<Favorite>>> getFavorites() {
    getFavoritesCalls++;
    return onGetFavorites!();
  }

  @override
  Future<Either<Failure, Favorite>> addFavorite(int mediaId) {
    addFavoriteCalls.add(mediaId);
    return onAddFavorite!(mediaId);
  }

  @override
  Future<Either<Failure, void>> removeFavorite(int mediaId) {
    removeFavoriteCalls.add(mediaId);
    return onRemoveFavorite!(mediaId);
  }

  @override
  Future<Either<Failure, Favorite>> addArtistFavorite(int artistId) async =>
      const Left(ServerFailure(message: 'not used'));

  @override
  Future<Either<Failure, void>> removeArtistFavorite(int artistId) async =>
      const Left(ServerFailure(message: 'not used'));
}

class FakeCollectionsRepository implements CollectionsRepository {
  Future<Either<Failure, List<Collection>>> Function()? onGetCollections;
  Future<Either<Failure, CollectionItem>> Function(int, int)? onAddItem;
  Future<Either<Failure, void>> Function(int, int)? onRemoveItem;
  Future<Either<Failure, List<Media>>> Function(int)? onGetItemsFull;

  int getItemsFullCalls = 0;
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
  ) {
    getItemsFullCalls++;
    return onGetItemsFull!(collectionId);
  }
}

class FakeLyricsRepository implements LyricsRepository {
  Future<Either<Failure, Lyrics?>> Function(int)? onGetLyrics;
  Future<Either<Failure, Lyrics>> Function(
    int, {
    required String lyricsText,
    required String source,
    String? translation,
    String? syncData,
  })? onUpsertLyrics;

  @override
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId) =>
      onGetLyrics!(mediaId);

  @override
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    required String source,
    String? translation,
    String? syncData,
  }) =>
      onUpsertLyrics!(
        mediaId,
        lyricsText: lyricsText,
        source: source,
        translation: translation,
        syncData: syncData,
      );
}

class FakeLyricsCacheRepository implements LyricsCacheRepository {
  final Map<int, Lyrics> cache = {};
  final List<(int, Lyrics)> saved = [];
  bool throwOnSave = false;

  @override
  Future<Lyrics?> getCachedLyrics(int mediaId) async => cache[mediaId];

  @override
  Future<void> saveLyrics(int mediaId, Lyrics lyrics) async {
    if (throwOnSave) throw Exception('Cache write failed');
    saved.add((mediaId, lyrics));
    cache[mediaId] = lyrics;
  }
}

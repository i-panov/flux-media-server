import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/metadata.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:flux_media_server/shared/models/user.dart';

void main() {
  group('Media', () {
    test('fromJson parses correctly with snake_case keys', () {
      final json = {
        'id': 1,
        'title': 'The Matrix',
        'year': 1999,
        'type': 'video',
        'file_size': 1024000,
        'description': 'A sci-fi classic',
        'duration': 8100,
        'thumbnail_url': 'http://example.com/thumb.jpg',
        'file_hash': 'abc123',
      };

      final media = Media.fromJson(json);

      expect(media.id, 1);
      expect(media.title, 'The Matrix');
      expect(media.year, 1999);
      expect(media.type, MediaType.video);
      expect(media.fileSize, 1024000);
      expect(media.description, 'A sci-fi classic');
      expect(media.duration, 8100);
      expect(media.thumbnailUrl, 'http://example.com/thumb.jpg');
      expect(media.fileHash, 'abc123');
    });

    test('fromJson with minimal fields', () {
      final json = {
        'id': 2,
        'title': 'Test',
        'year': 2024,
        'type': 'video',
        'file_size': 512,
      };

      final media = Media.fromJson(json);

      expect(media.description, isNull);
      expect(media.duration, isNull);
      expect(media.thumbnailUrl, isNull);
      expect(media.fileHash, '');
    });

    test('unknown type becomes MediaType.unknown, not video', () {
      final json = {
        'id': 3,
        'title': 'Mystery',
        'type': 'ebook',
        'file_size': 1,
      };

      final media = Media.fromJson(json);

      expect(media.type, MediaType.unknown);
    });

    test('empty type becomes MediaType.unknown (consistent)', () {
      final json = {
        'id': 4,
        'title': 'No Type',
        'type': '',
        'file_size': 1,
      };

      final media = Media.fromJson(json);

      expect(media.type, MediaType.unknown);
    });

    test('equality works', () {
      const a = Media(
        id: 1,
        title: 'Test',
        year: 2024,
        type: MediaType.video,
        fileSize: 100,
      );
      const b = Media(
        id: 1,
        title: 'Test',
        year: 2024,
        type: MediaType.video,
        fileSize: 100,
      );

      expect(a, equals(b));
    });

    test('toJson to fromJson roundtrip (offline cache path)', () {
      final media = Media(
        id: 7,
        title: 'Roundtrip Media',
        year: 2024,
        type: MediaType.audio,
        fileSize: 2048,
        filename: 'song.mp3',
        duration: 180,
        thumbnailUrl: 'http://example.com/thumb.jpg',
        coverUrl: 'http://example.com/cover.jpg',
        artists: const [
          Artist(id: 1, name: 'Artist One'),
          Artist(id: 2, name: 'Artist Two'),
        ],
        album: 'Album',
        genre: 'Rock',
        metadata: const Metadata(
          id: 9,
          title: 'Meta Title',
          genres: ['Rock', 'Indie'],
          cast: ['Member'],
        ),
        fileHash: 'abc123',
        updatedAt: DateTime.utc(2024, 5, 1, 12, 30),
      );

      final restored = Media.fromJson(media.toJson());

      expect(restored, equals(media));
      expect(restored.artists, hasLength(2));
      expect(restored.metadata?.genres, ['Rock', 'Indie']);
      expect(restored.type, MediaType.audio);
    });

    test('unknown type survives toJson to fromJson roundtrip', () {
      const media = Media(
        id: 8,
        title: 'Mystery',
        type: MediaType.unknown,
        fileSize: 1,
      );

      final restored = Media.fromJson(media.toJson());

      expect(restored.type, MediaType.unknown);
    });

    test('missing type becomes MediaType.unknown, not crash', () {
      final media = Media.fromJson({
        'id': 9,
        'title': 'No type key',
        'file_size': 1,
      });

      expect(media.type, MediaType.unknown);
    });

    test('null type becomes MediaType.unknown, not crash', () {
      final media = Media.fromJson({
        'id': 10,
        'title': 'Null type',
        'type': null,
        'file_size': 1,
      });

      expect(media.type, MediaType.unknown);
    });

    test('type value is normalized (case and whitespace)', () {
      final media = Media.fromJson({
        'id': 11,
        'title': 'Mixed case',
        'type': 'Video',
        'file_size': 1,
      });

      expect(media.type, MediaType.video);

      final padded = Media.fromJson({
        'id': 12,
        'title': 'Padded',
        'type': '  audio ',
        'file_size': 1,
      });

      expect(padded.type, MediaType.audio);
    });

    test('createdAt parses from created_at and survives roundtrip', () {
      final media = Media.fromJson({
        'id': 13,
        'title': 'With created_at',
        'type': 'video',
        'file_size': 1,
        'created_at': '2024-06-01T10:00:00Z',
      });

      expect(media.createdAt, DateTime.utc(2024, 6, 1, 10));
      expect(Media.fromJson(media.toJson()), equals(media));
    });

    test('updatedAt is null when updated_at is missing (roundtrip)', () {
      const media = Media(
        id: 14,
        title: 'No updated_at',
        type: MediaType.video,
        fileSize: 1,
      );

      expect(media.updatedAt, isNull);
      final restored = Media.fromJson(media.toJson());
      expect(restored.updatedAt, isNull);
      expect(restored, equals(media));
    });
  });

  group('User', () {
    test('fromJson parses correctly', () {
      final user = User.fromJson({'id': 1, 'email': 'test@example.com'});
      expect(user.id, 1);
      expect(user.email, 'test@example.com');
    });

    test('isAdmin defaults to false and parses is_admin', () {
      final plain = User.fromJson({'id': 1, 'email': 'a@b.c'});
      expect(plain.isAdmin, isFalse);

      final admin =
          User.fromJson({'id': 2, 'email': 'a@b.c', 'is_admin': true});
      expect(admin.isAdmin, isTrue);
    });

    test('toJson to fromJson roundtrip', () {
      const user = User(id: 3, email: 'round@trip.io', isAdmin: true);
      expect(User.fromJson(user.toJson()), equals(user));
    });
  });

  group('WatchProgress', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'user_id': 1,
        'media_id': 1,
        'position': 3600,
      };

      final progress = WatchProgress.fromJson(json);

      expect(progress.id, 1);
      expect(progress.userId, 1);
      expect(progress.mediaId, 1);
      expect(progress.position, 3600);
    });
  });

  group('Metadata', () {
    test('fromJson parses correctly with string-encoded lists', () {
      final json = {
        'id': 1,
        'external_id': 'tmdb-123',
        'source': 'tmdb',
        'title': 'The Matrix',
        'year': 1999,
        'description': 'Sci-fi',
        'poster_url': 'http://example.com/poster.jpg',
        'backdrop_url': 'http://example.com/backdrop.jpg',
        'rating': 8.7,
        'genres': '["Action","Sci-Fi"]',
        'cast': '["Keanu Reeves"]',
      };

      final meta = Metadata.fromJson(json);

      expect(meta.id, 1);
      expect(meta.externalId, 'tmdb-123');
      expect(meta.source, 'tmdb');
      expect(meta.title, 'The Matrix');
      expect(meta.rating, 8.7);
      expect(meta.genres, ['Action', 'Sci-Fi']);
      expect(meta.cast, ['Keanu Reeves']);
    });

    test('fromJson parses correctly with regular lists', () {
      final json = {
        'id': 2,
        'external_id': 'tmdb-456',
        'source': 'tmdb',
        'title': 'Inception',
        'year': 2010,
        'poster_url': 'http://example.com/poster2.jpg',
        'backdrop_url': 'http://example.com/backdrop2.jpg',
        'rating': 8.8,
        'genres': ['Action', 'Sci-Fi', 'Adventure'],
        'cast': ['Leonardo DiCaprio', 'Joseph Gordon-Levitt'],
      };

      final meta = Metadata.fromJson(json);

      expect(meta.id, 2);
      expect(meta.genres, ['Action', 'Sci-Fi', 'Adventure']);
      expect(meta.cast, ['Leonardo DiCaprio', 'Joseph Gordon-Levitt']);
    });

    test('toJson writes genres/cast as JSON strings (roundtrip)', () {
      const meta = Metadata(
        id: 3,
        title: 'Roundtrip',
        genres: ['Action', 'Sci-Fi'],
        cast: ['Keanu Reeves', 'Carrie-Anne Moss'],
      );

      final json = meta.toJson();

      expect(json['genres'], '["Action","Sci-Fi"]');
      expect(json['cast'], '["Keanu Reeves","Carrie-Anne Moss"]');

      final restored = Metadata.fromJson(json);
      expect(restored.genres, meta.genres);
      expect(restored.cast, meta.cast);
    });

    test('toJson to fromJson roundtrip with null lists', () {
      const meta = Metadata(
        id: 4,
        title: 'No lists',
        description: 'Nothing here',
      );

      final json = meta.toJson();
      expect(json['genres'], isNull);
      expect(json['cast'], isNull);

      final restored = Metadata.fromJson(json);
      expect(restored, equals(meta));
      expect(restored.genres, isNull);
      expect(restored.cast, isNull);
    });

    test('invalid JSON string in genres/cast yields empty list, not crash',
        () {
      final meta = Metadata.fromJson({
        'id': 6,
        'title': 'Broken genres',
        'genres': '{not valid json',
        'cast': 'nope',
      });

      expect(meta.genres, isEmpty);
      expect(meta.cast, isEmpty);
    });

    test('list with non-strings in genres/cast yields empty list, not crash',
        () {
      final meta = Metadata.fromJson({
        'id': 7,
        'title': 'Mixed genres',
        'genres': ['Rock', 42, null],
        'cast': [1, 2],
      });

      expect(meta.genres, isEmpty);
      expect(meta.cast, isEmpty);
    });

    test('equality works', () {
      const a = Metadata(id: 5, title: 'T', genres: ['A']);
      const b = Metadata(id: 5, title: 'T', genres: ['A']);
      expect(a, equals(b));
      const c = Metadata(id: 5, title: 'T', genres: ['B']);
      expect(a, isNot(equals(c)));
    });
  });

  group('Artist', () {
    test('fromJson parses correctly', () {
      final artist = Artist.fromJson({'id': 1, 'name': 'The Band'});
      expect(artist.id, 1);
      expect(artist.name, 'The Band');
    });

    test('equality works', () {
      const a = Artist(id: 1, name: 'X');
      const b = Artist(id: 1, name: 'X');
      expect(a, equals(b));
      expect(a, isNot(equals(const Artist(id: 2, name: 'X'))));
    });

    test('position parses, defaults to 0 and survives roundtrip', () {
      final plain = Artist.fromJson({'id': 3, 'name': 'No Position'});
      expect(plain.position, 0);

      const ordered = Artist(id: 4, name: 'First', position: 1);
      expect(Artist.fromJson(ordered.toJson()), equals(ordered));
    });
  });

  group('Collection', () {
    test('fromJson parses snake_case fields and type', () {
      final json = {
        'id': 1,
        'user_id': 7,
        'name': 'My collection',
        'type': 'audio',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-02-01T00:00:00Z',
      };

      final collection = Collection.fromJson(json);

      expect(collection.id, 1);
      expect(collection.userId, 7);
      expect(collection.name, 'My collection');
      expect(collection.type, MediaType.audio);
      expect(collection.createdAt, DateTime.utc(2024));
      expect(collection.updatedAt, DateTime.utc(2024, 2));
    });

    test('unknown type becomes MediaType.unknown', () {
      final json = {
        'id': 2,
        'user_id': 7,
        'name': 'C',
        'type': 'podcast',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
      };

      expect(Collection.fromJson(json).type, MediaType.unknown);
    });

    test('toJson to fromJson roundtrip', () {
      final collection = Collection(
        id: 3,
        userId: 7,
        name: 'Roundtrip',
        type: MediaType.video,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024, 2, 2),
      );

      final restored = Collection.fromJson(collection.toJson());
      expect(restored, equals(collection));
      expect(restored.type, MediaType.video);
    });
  });

  group('CollectionItem', () {
    test('fromJson parses full object', () {
      final json = {
        'id': 1,
        'collection_id': 3,
        'media_id': 5,
        'added_at': '2024-03-01T00:00:00Z',
        'position': 2,
      };

      final item = CollectionItem.fromJson(json);

      expect(item.id, 1);
      expect(item.collectionId, 3);
      expect(item.mediaId, 5);
      expect(item.addedAt, DateTime.utc(2024, 3));
      expect(item.position, 2);
    });

    test('fromJson with only id leaves nullable fields null', () {
      final item = CollectionItem.fromJson({'id': 2});

      expect(item.id, 2);
      expect(item.collectionId, isNull);
      expect(item.mediaId, isNull);
      expect(item.addedAt, isNull);
      expect(item.position, isNull);
    });

    test('toJson to fromJson roundtrip', () {
      final item = CollectionItem(
        id: 3,
        collectionId: 3,
        mediaId: 5,
        addedAt: DateTime.utc(2024, 3),
        position: 2,
      );

      expect(CollectionItem.fromJson(item.toJson()), equals(item));
    });
  });

  group('Favorite', () {
    test('fromJson parses media favorite', () {
      final json = {
        'id': 1,
        'user_id': 7,
        'created_at': '2024-01-01T00:00:00Z',
        'media_id': 5,
      };

      final favorite = Favorite.fromJson(json);

      expect(favorite.id, 1);
      expect(favorite.userId, 7);
      expect(favorite.mediaId, 5);
      expect(favorite.artistId, isNull);
    });

    test('fromJson parses artist favorite without media_id', () {
      final json = {
        'id': 2,
        'user_id': 7,
        'created_at': '2024-01-01T00:00:00Z',
        'artist_id': 3,
      };

      final favorite = Favorite.fromJson(json);

      expect(favorite.mediaId, isNull);
      expect(favorite.artistId, 3);
    });

    test('equality works', () {
      final a = Favorite(
        id: 1,
        userId: 7,
        createdAt: DateTime.utc(2024),
        mediaId: 5,
      );
      final b = Favorite(
        id: 1,
        userId: 7,
        createdAt: DateTime.utc(2024),
        mediaId: 5,
      );
      expect(a, equals(b));
    });

    test('toJson to fromJson roundtrip', () {
      final favorite = Favorite(
        id: 2,
        userId: 7,
        createdAt: DateTime.utc(2024),
        artistId: 3,
      );

      final restored = Favorite.fromJson(favorite.toJson());
      expect(restored, equals(favorite));
      expect(restored.artistId, 3);
    });
  });

  group('Lyrics', () {
    final baseJson = {
      'id': 1,
      'media_id': 5,
      'source': 'musixmatch',
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-02-01T00:00:00Z',
    };

    test('fromJson parses with defaults', () {
      final lyrics = Lyrics.fromJson(baseJson);

      expect(lyrics.id, 1);
      expect(lyrics.mediaId, 5);
      expect(lyrics.source, 'musixmatch');
      expect(lyrics.lyricsText, '');
      expect(lyrics.translation, '');
      expect(lyrics.syncData, '');
    });

    test('fromJson parses text fields', () {
      final lyrics = Lyrics.fromJson({
        ...baseJson,
        'lyrics_text': 'La la',
        'translation': 'Тра-ля',
        'sync_data': '[0.0]La',
      });

      expect(lyrics.lyricsText, 'La la');
      expect(lyrics.translation, 'Тра-ля');
      expect(lyrics.syncData, '[0.0]La');
    });

    test('toJson to fromJson roundtrip and equality', () {
      final lyrics = Lyrics(
        id: 2,
        mediaId: 6,
        source: 'manual',
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024, 2),
        lyricsText: 'Text',
        translation: 'Перевод',
      );

      final restored = Lyrics.fromJson(lyrics.toJson());

      expect(restored, equals(lyrics));
    });
  });

  group('WatchProgress extra fields', () {
    test('fromJson parses duration, completed and updated_at', () {
      final json = {
        'id': 1,
        'user_id': 7,
        'media_id': 5,
        'position': 3600,
        'duration': 7200,
        'completed': true,
        'updated_at': '2024-04-01T00:00:00Z',
      };

      final progress = WatchProgress.fromJson(json);

      expect(progress.duration, 7200);
      expect(progress.completed, isTrue);
      expect(progress.updatedAt, DateTime.utc(2024, 4));
    });

    test('defaults duration/completed when absent', () {
      final progress = WatchProgress.fromJson({
        'id': 1,
        'user_id': 7,
        'media_id': 5,
        'position': 0,
      });

      expect(progress.duration, 0);
      expect(progress.completed, isFalse);
      expect(progress.updatedAt, isNull);
    });

    test('id is optional on the client and survives roundtrip', () {
      const local = WatchProgress(
        userId: 7,
        mediaId: 5,
        position: 100,
        duration: 200,
        completed: true,
      );

      expect(local.id, isNull);
      expect(
        const WatchProgress(userId: 7, mediaId: 5, position: 0),
        equals(const WatchProgress(userId: 7, mediaId: 5, position: 0)),
      );

      final restored = WatchProgress.fromJson(local.toJson());
      expect(restored, equals(local));
      expect(restored.id, isNull);
    });

    test('toJson to fromJson roundtrip with id', () {
      final progress = WatchProgress(
        id: 9,
        userId: 7,
        mediaId: 5,
        position: 3600,
        duration: 7200,
        updatedAt: DateTime.utc(2024, 4),
      );

      final restored = WatchProgress.fromJson(progress.toJson());
      expect(restored, equals(progress));
    });
  });
}

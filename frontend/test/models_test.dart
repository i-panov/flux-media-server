import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:flux_media_server/shared/models/metadata.dart';

void main() {
  group('Media', () {
    test('fromJson parses correctly with camelCase keys', () {
      final json = {
        'id': 1,
        'title': 'The Matrix',
        'year': 1999,
        'type': 'movie',
        'filePath': '/movies/matrix.mkv',
        'fileSize': 1024000,
        'description': 'A sci-fi classic',
        'duration': 8100,
        'thumbnailUrl': 'http://example.com/thumb.jpg',
        'fileHash': 'abc123',
      };

      final media = Media.fromJson(json);

      expect(media.id, 1);
      expect(media.title, 'The Matrix');
      expect(media.year, 1999);
      expect(media.type, 'movie');
      expect(media.filePath, '/movies/matrix.mkv');
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
        'type': 'episode',
        'filePath': '/test.mp4',
        'fileSize': 512,
      };

      final media = Media.fromJson(json);

      expect(media.description, isNull);
      expect(media.duration, isNull);
      expect(media.thumbnailUrl, isNull);
      expect(media.fileHash, '');
    });

    test('equality works', () {
      final a = Media(
        id: 1,
        title: 'Test',
        year: 2024,
        type: 'movie',
        filePath: '/test.mp4',
        fileSize: 100,
      );
      final b = Media(
        id: 1,
        title: 'Test',
        year: 2024,
        type: 'movie',
        filePath: '/test.mp4',
        fileSize: 100,
      );

      expect(a, equals(b));
    });
  });

  group('User', () {
    test('fromJson parses correctly', () {
      final user = User.fromJson({'id': 1, 'email': 'test@example.com'});
      expect(user.id, 1);
      expect(user.email, 'test@example.com');
    });
  });

  group('MediaLibrary', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'name': 'Movies',
        'path': '/media/movies',
        'type': 'movie',
        'enabled': true,
        'scanInterval': 30,
      };

      final lib = MediaLibrary.fromJson(json);

      expect(lib.id, 1);
      expect(lib.name, 'Movies');
      expect(lib.path, '/media/movies');
      expect(lib.type, 'movie');
      expect(lib.enabled, true);
      expect(lib.scanInterval, 30);
    });
  });

  group('WatchProgress', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'userId': 1,
        'mediaId': 1,
        'position': 3600,
        'duration': 7200,
        'completed': false,
      };

      final progress = WatchProgress.fromJson(json);

      expect(progress.id, 1);
      expect(progress.userId, 1);
      expect(progress.mediaId, 1);
      expect(progress.position, 3600);
      expect(progress.duration, 7200);
      expect(progress.completed, false);
    });
  });

  group('Metadata', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'externalId': 'tmdb-123',
        'source': 'tmdb',
        'title': 'The Matrix',
        'year': 1999,
        'description': 'Sci-fi',
        'posterUrl': 'http://example.com/poster.jpg',
        'backdropUrl': 'http://example.com/backdrop.jpg',
        'rating': 8.7,
        'genres': ['Action', 'Sci-Fi'],
        'cast': ['Keanu Reeves'],
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
  });
}

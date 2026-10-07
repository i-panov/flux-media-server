import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/utils/media_image_url.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _media({
  int id = 1,
  String? coverUrl,
  String? thumbnailUrl,
  DateTime? updatedAt,
}) => Media(
  id: id,
  title: 'T',
  type: MediaType.video,
  fileSize: 1,
  coverUrl: coverUrl,
  thumbnailUrl: thumbnailUrl,
  updatedAt: updatedAt,
);

void main() {
  const base = 'https://host/api';

  group('mediaImageKindFor', () {
    test('prefers the cover when it is uploaded', () {
      final media = _media(coverUrl: '/x', thumbnailUrl: '/y');
      expect(mediaImageKindFor(media), MediaImageKind.cover);
    });

    test('falls back to the thumb when only a thumbnail exists', () {
      // Регресс: трек без обложки запрашивал /cover и получал 404.
      final media = _media(thumbnailUrl: '/y');
      expect(mediaImageKindFor(media), MediaImageKind.thumb);
    });

    test('falls back to the thumb for an empty cover url', () {
      expect(mediaImageKindFor(_media(coverUrl: '')), MediaImageKind.thumb);
      expect(mediaImageKindFor(_media()), MediaImageKind.thumb);
    });
  });

  group('buildMediaImageUrl', () {
    test('builds cover and thumb paths with the api base', () {
      expect(
        buildMediaImageUrl(
          baseUrl: base,
          mediaId: 7,
          kind: MediaImageKind.cover,
        ),
        'https://host/api/media/7/cover',
      );
      expect(
        buildMediaImageUrl(
          baseUrl: base,
          mediaId: 7,
          kind: MediaImageKind.thumb,
        ),
        'https://host/api/media/7/thumb',
      );
    });

    test('appends cacheBust when updatedAt is known', () {
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(1700);
      expect(
        buildMediaImageUrl(
          baseUrl: base,
          mediaId: 7,
          kind: MediaImageKind.cover,
          cacheBust: updatedAt.millisecondsSinceEpoch,
        ),
        'https://host/api/media/7/cover?v=1700',
      );
    });
  });

  group('buildArtistCoverUrl', () {
    test('builds the artist cover path', () {
      expect(
        buildArtistCoverUrl(baseUrl: base, artistId: 3),
        'https://host/api/artists/3/cover',
      );
      expect(
        buildArtistCoverUrl(baseUrl: base, artistId: 3, cacheBust: 42),
        'https://host/api/artists/3/cover?v=42',
      );
    });
  });

  group('hasMediaYear', () {
    test('treats 0 and null as missing', () {
      expect(hasMediaYear(null), isFalse);
      expect(hasMediaYear(0), isFalse);
      expect(hasMediaYear(-5), isFalse);
      expect(hasMediaYear(1999), isTrue);
    });
  });
}

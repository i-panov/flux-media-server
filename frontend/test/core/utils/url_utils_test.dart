import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';

void main() {
  group('isValidServerUrl', () {
    test('accepts http/https URLs with host', () {
      expect(isValidServerUrl('http://localhost:8080'), isTrue);
      expect(isValidServerUrl('https://example.com/api'), isTrue);
      expect(isValidServerUrl('  http://10.0.0.5:8080  '), isTrue);
    });

    test('rejects empty, schemeless and non-http URLs', () {
      expect(isValidServerUrl(''), isFalse);
      expect(isValidServerUrl('   '), isFalse);
      expect(isValidServerUrl('localhost:8080'), isFalse);
      expect(isValidServerUrl('ftp://example.com'), isFalse);
      expect(isValidServerUrl('http://'), isFalse);
    });
  });

  group('isValidHttpUrl', () {
    test('accepts complete http(s) links', () {
      expect(isValidHttpUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(isValidHttpUrl('https://youtu.be/abc'), isTrue);
      expect(isValidHttpUrl('  http://example.com/x  '), isTrue);
    });

    test('rejects empty, schemeless and non-http URLs', () {
      expect(isValidHttpUrl(''), isFalse);
      expect(isValidHttpUrl('   '), isFalse);
      expect(isValidHttpUrl('youtube.com/watch'), isFalse);
      expect(isValidHttpUrl('ftp://example.com/x'), isFalse);
      expect(isValidHttpUrl('javascript:alert(1)'), isFalse);
      expect(isValidHttpUrl('https://'), isFalse);
    });

    test('rejects URLs longer than the server limit (2048)', () {
      final ok = 'https://example.com/${'a' * 2000}';
      expect(ok.runes.length, lessThanOrEqualTo(2048));
      expect(isValidHttpUrl(ok), isTrue);

      final tooLong = 'https://example.com/${'a' * 2041}';
      expect(tooLong.runes.length, greaterThan(2048));
      expect(isValidHttpUrl(tooLong), isFalse);
    });

    test('exact boundary: 2048 runes OK, 2049 FAIL', () {
      // 'https://example.com/' — 20 символов, остальное добиваем 'a'.
      const base = 'https://example.com/';
      final exactly = base + 'a' * (2048 - base.length);
      expect(exactly.runes.length, 2048);
      expect(isValidHttpUrl(exactly), isTrue);

      final over = base + 'a' * (2049 - base.length);
      expect(over.runes.length, 2049);
      expect(isValidHttpUrl(over), isFalse);
    });

    test('emoji counts as one rune, not two UTF-16 units', () {
      // '😀' — 1 руна, 2 юнита UTF-16: лимит считаем как сервер.
      final emojiOk = 'https://example.com/${'😀' * 2028}';
      expect(emojiOk.runes.length, 2048);
      expect(emojiOk.length, greaterThan(2048));
      expect(isValidHttpUrl(emojiOk), isTrue);

      final emojiOver = 'https://example.com/${'😀' * 2029}';
      expect(emojiOver.runes.length, 2049);
      expect(isValidHttpUrl(emojiOver), isFalse);
    });

    test('server URL has no length limit', () {
      // isValidServerUrl делит только схему и хост; длинные пути
      // (токены в query и т.п.) ему не мешают.
      final long = 'https://example.com/${'a' * 5000}';
      expect(isValidServerUrl(long), isTrue);
    });
  });

  group('normalizeServerUrl', () {
    test('adds /api segment and strips trailing slash', () {
      expect(
        normalizeServerUrl('http://localhost:8080'),
        'http://localhost:8080/api',
      );
      expect(
        normalizeServerUrl('http://localhost:8080/'),
        'http://localhost:8080/api',
      );
    });

    test('keeps existing /api segment', () {
      expect(
        normalizeServerUrl('http://localhost:8080/api'),
        'http://localhost:8080/api',
      );
      expect(
        normalizeServerUrl('http://localhost:8080/api/'),
        'http://localhost:8080/api',
      );
    });

    test('adds default scheme and trims whitespace', () {
      expect(
        normalizeServerUrl('  localhost:8080  '),
        'http://localhost:8080/api',
      );
    });

    test('collapses duplicate slashes', () {
      expect(
        normalizeServerUrl('http://localhost:8080//api//'),
        'http://localhost:8080/api',
      );
    });

    test('appends /api after a custom subpath', () {
      expect(
        normalizeServerUrl('http://host:8080/flux'),
        'http://host:8080/flux/api',
      );
    });

    test('keeps subpath that already contains api', () {
      expect(
        normalizeServerUrl('http://host:8080/api/v2'),
        'http://host:8080/api/v2',
      );
    });

    test('drops userInfo from the URL', () {
      expect(
        normalizeServerUrl('http://user:pass@host:8080'),
        'http://host:8080/api',
      );
      expect(normalizeServerUrl('https://user@host/api'), 'https://host/api');
    });
  });
}

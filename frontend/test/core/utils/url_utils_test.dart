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
  });
}

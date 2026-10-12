import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/offline/data/cache_naming.dart';

void main() {
  group('CacheNaming (debug)', () {
    const naming = CacheNaming(userId: 7, debugOverride: true);

    test('файлы и ключи содержат user-неймспейс', () {
      expect(naming.fileName(5), 'debug_user_7_flux_media_5');
      expect(naming.metaKey(5), 'debug_user_7_flux_meta_5');
      expect(naming.lyricsKey(5), 'debug_user_7_flux_lyrics_5');
    });

    test('служебные ключи', () {
      expect(naming.userIdKey, 'debug_flux_current_user_id');
      expect(naming.migratedKey(7), 'debug_flux_migrated_user_7');
      expect(naming.userFilePrefix, 'debug_user_7_');
      expect(naming.anyUserPrefix, 'debug_user_');
    });

    test('легаси-ключи без user-неймспейса', () {
      expect(naming.legacyMetaKey(3), 'debug_flux_meta_3');
      expect(naming.legacyLyricsKey(3), 'debug_flux_lyrics_3');
    });

    test('разные пользователи не пересекаются', () {
      const other = CacheNaming(userId: 9, debugOverride: true);
      expect(other.fileName(5), isNot(naming.fileName(5)));
      expect(other.metaKey(5), isNot(naming.metaKey(5)));
      expect(other.userFilePrefix, isNot(naming.userFilePrefix));
    });
  });

  group('CacheNaming (release)', () {
    const naming = CacheNaming(userId: 7, debugOverride: false);

    test('другой префикс, тот же формат', () {
      expect(naming.fileName(5), 'release_user_7_flux_media_5');
      expect(naming.metaKey(5), 'release_user_7_flux_meta_5');
      expect(naming.userIdKey, 'release_flux_current_user_id');
    });

    test('сборки не делят кеш', () {
      const debug = CacheNaming(userId: 7, debugOverride: true);
      expect(naming.fileName(5), isNot(debug.fileName(5)));
    });
  });

  group('CacheNaming (неизвестный пользователь)', () {
    const naming = CacheNaming(userId: 0, debugOverride: true);

    test('фолбэк на user_0_', () {
      expect(naming.fileName(5), 'debug_user_0_flux_media_5');
      expect(naming.userFilePrefix, 'debug_user_0_');
    });
  });
}

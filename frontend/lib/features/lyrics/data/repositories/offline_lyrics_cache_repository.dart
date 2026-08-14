import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_cache_repository.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

/// Реализация [LyricsCacheRepository] поверх [OfflineCacheService].
class OfflineLyricsCacheRepository implements LyricsCacheRepository {
  OfflineLyricsCacheRepository(this._cacheService);

  final OfflineCacheService _cacheService;

  @override
  Future<Lyrics?> getCachedLyrics(int mediaId) {
    return _cacheService.getCachedLyrics(mediaId);
  }

  @override
  Future<void> saveLyrics(int mediaId, Lyrics lyrics) {
    return _cacheService.saveLyrics(mediaId, lyrics);
  }
}

/// Провайдер зарегистрирован в data-слое: presentation фичи lyrics
/// не должен импортировать data другой фичи (offline).
final lyricsCacheRepositoryProvider = Provider<LyricsCacheRepository>((ref) {
  return OfflineLyricsCacheRepository(ref.watch(offlineCacheServiceProvider));
});

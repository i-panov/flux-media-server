import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/lyrics/data/datasources/lyrics_remote_datasource.dart';
import 'package:flux_media_server/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/get_lyrics.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/upsert_lyrics.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
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
/// Falls back to locally cached lyrics when the server is unreachable.
final lyricsProvider =
    FutureProvider.autoDispose.family<Lyrics?, int>((ref, mediaId) async {
  final getLyrics = ref.watch(getLyricsProvider);
  final result = await getLyrics(mediaId);
  return result.fold(
    (failure) {
      // API failed — try local cache (offline mode).
      final cacheService = ref.read(offlineCacheServiceProvider);
      final cached = cacheService.getCachedLyrics(mediaId);
      return cached;
    },
    (lyrics) {
      // Persist lyrics for offline access.
      if (lyrics != null) {
        ref.read(offlineCacheServiceProvider).saveLyrics(mediaId, lyrics);
      }
      return lyrics;
    },
  );
});

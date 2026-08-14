import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/lyrics/data/datasources/lyrics_remote_datasource.dart';
import 'package:flux_media_server/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:flux_media_server/features/lyrics/data/repositories/offline_lyrics_cache_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/get_lyrics.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/upsert_lyrics.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

final lyricsRemoteDataSourceProvider = Provider<LyricsRemoteDataSource>((ref) {
  return LyricsRemoteDataSource(ref.watch(mediaApiClientProvider));
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

/// Результат загрузки лирики.
///
/// Отличает «нет лирики» от сетевой ошибки: при ошибке сети с наличием
/// офлайн-копии возвращаем её с [fromCache] = true; если копии нет —
/// пробрасываем ошибку (AsyncError в провайдере).
class LyricsLoadResult {
  const LyricsLoadResult({
    required this.lyrics,
    this.fromCache = false,
  });

  final Lyrics? lyrics;
  final bool fromCache;
}

/// Fetches lyrics for a media item. Returns null if no lyrics exist.
/// Falls back to locally cached lyrics when the server is unreachable.
///
/// keepAlive: переключение вкладок (лирика/перевод) не должно вызывать
/// повторный GET на каждое переключение.
final lyricsProvider =
    FutureProvider.autoDispose.family<LyricsLoadResult, int>(
  (ref, mediaId) async {
    final keepAlive = ref.keepAlive();
    ref.onDispose(keepAlive.close);

    final getLyrics = ref.watch(getLyricsProvider);
    final result = await getLyrics(mediaId);
    return result.fold(
      (failure) async {
        // API failed — try local cache (offline mode).
        final cache = ref.read(lyricsCacheRepositoryProvider);
        final cached = await cache.getCachedLyrics(mediaId);
        if (cached != null) {
          return LyricsLoadResult(lyrics: cached, fromCache: true);
        }
        // Сетевая ошибка не маскируется под «нет лирики».
        throw Exception(failure.message);
      },
      (lyrics) async {
        // Persist lyrics for offline access (ждём сохранения).
        if (lyrics != null) {
          await ref.read(lyricsCacheRepositoryProvider).saveLyrics(
                mediaId,
                lyrics,
              );
        }
        return LyricsLoadResult(lyrics: lyrics);
      },
    );
  },
);

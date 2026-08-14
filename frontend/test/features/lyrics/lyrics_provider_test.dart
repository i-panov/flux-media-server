import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/lyrics/data/repositories/offline_lyrics_cache_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_cache_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/get_lyrics.dart';
import 'package:flux_media_server/features/lyrics/presentation/providers/lyrics_provider.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:fpdart/fpdart.dart';

Lyrics _lyrics([int mediaId = 5]) => Lyrics(
      id: 1,
      mediaId: mediaId,
      source: 'musixmatch',
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
      lyricsText: 'La la la',
      translation: 'Ля-ля-ля',
    );

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

  @override
  Future<Lyrics?> getCachedLyrics(int mediaId) async => cache[mediaId];

  @override
  Future<void> saveLyrics(int mediaId, Lyrics lyrics) async {
    saved.add((mediaId, lyrics));
    cache[mediaId] = lyrics;
  }
}

void main() {
  late ProviderContainer container;
  late FakeLyricsRepository fakeRepo;
  late FakeLyricsCacheRepository fakeCache;

  setUp(() {
    fakeRepo = FakeLyricsRepository();
    fakeCache = FakeLyricsCacheRepository();
    container = ProviderContainer(
      overrides: [
        getLyricsProvider.overrideWithValue(GetLyrics(fakeRepo)),
        lyricsCacheRepositoryProvider.overrideWithValue(fakeCache),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('lyricsProvider', () {
    test('returns lyrics and persists them to cache', () async {
      final lyrics = _lyrics();
      fakeRepo.onGetLyrics = (_) async => Right(lyrics);

      final result = await container.read(lyricsProvider(5).future);

      expect(result.lyrics, lyrics);
      expect(result.fromCache, isFalse);
      // Сохранение awaited: к моменту завершения провайдера кеш заполнен.
      expect(fakeCache.cache[5], lyrics);
      expect(fakeCache.saved, [(5, lyrics)]);
    });

    test('returns empty result when the server has no lyrics', () async {
      fakeRepo.onGetLyrics = (_) async => const Right(null);

      final result = await container.read(lyricsProvider(5).future);

      expect(result.lyrics, isNull);
      expect(result.fromCache, isFalse);
      expect(fakeCache.saved, isEmpty);
    });

    test('falls back to cached lyrics on network failure', () async {
      final cached = _lyrics();
      fakeCache.cache[5] = cached;
      fakeRepo.onGetLyrics =
          (_) async => const Left(NetworkFailure(message: 'Offline'));

      final result = await container.read(lyricsProvider(5).future);

      expect(result.lyrics, cached);
      expect(result.fromCache, isTrue);
    });

    test('throws on failure when there is no cached copy', () async {
      fakeRepo.onGetLyrics =
          (_) async => const Left(NetworkFailure(message: 'Offline'));

      await expectLater(
        container.read(lyricsProvider(5).future),
        throwsA(isA<Exception>()),
      );
      final state = container.read(lyricsProvider(5));
      expect(state.hasError, isTrue);
    });
  });
}

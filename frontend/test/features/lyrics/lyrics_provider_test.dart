import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/lyrics/data/repositories/offline_lyrics_cache_repository.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/get_lyrics.dart';
import 'package:flux_media_server/features/lyrics/presentation/providers/lyrics_provider.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/fake_repositories.dart';

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
      final data = fakeLyrics();
      fakeRepo.onGetLyrics = (_) async => Right(data);

      final result = await container.read(lyricsProvider(5).future);
      // Кеш-запись fire-and-forget — дожидаемся её фонового завершения.
      await pumpEventQueue();

      expect(result.lyrics, data);
      expect(result.fromCache, isFalse);
      expect(fakeCache.cache[5], data);
      expect(fakeCache.saved, [(5, data)]);
    });

    test('cache write failure does not fail the provider', () async {
      final data = fakeLyrics();
      fakeRepo.onGetLyrics = (_) async => Right(data);
      fakeCache.throwOnSave = true;

      final result = await container.read(lyricsProvider(5).future);
      await pumpEventQueue();

      // Успешный GET не превращается в AsyncError из-за сбоя кеша.
      expect(result.lyrics, data);
      expect(container.read(lyricsProvider(5)).hasError, isFalse);
    });

    test('returns empty result when the server has no lyrics', () async {
      fakeRepo.onGetLyrics = (_) async => const Right(null);

      final result = await container.read(lyricsProvider(5).future);

      expect(result.lyrics, isNull);
      expect(result.fromCache, isFalse);
      expect(fakeCache.saved, isEmpty);
    });

    test('falls back to cached lyrics on network failure', () async {
      final cached = fakeLyrics();
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

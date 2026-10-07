import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _media(int id) => Media(
  id: id,
  title: 'Media $id',
  year: 2024,
  type: MediaType.video,
  fileSize: 1024,
);

/// Фейк кеш-сервиса: isCached завершается вручную, download мгновенный.
class _ControllableCache extends OfflineCacheService {
  new(super.ref, super.baseUrl);

  final Completer<bool> isCachedCompleter = Completer<bool>();
  int downloadCalls = 0;

  @override
  Future<bool> isCached(int mediaId) => isCachedCompleter.future;

  @override
  Future<String> download(
    Media media, {
    void Function(int received, int? total)? onProgress,
  }) async {
    downloadCalls++;
    onProgress?.call(10, 10);
    return 'local';
  }

  @override
  Future<void> remove(int mediaId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _ControllableCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineCacheServiceProvider.overrideWith(
          (ref) => cache = _ControllableCache(ref, ''),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> flush() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('DownloadsStateNotifier.checkStatus', () {
    test('applies cached result when idle', () async {
      final downloads = container.read(downloadsStateProvider.notifier);
      // Проверка уходит в фон и ждёт isCachedCompleter.
      unawaited(downloads.checkStatus(1));
      expect(downloads.stateOf(1), isA<DownloadIdle>());

      cache.isCachedCompleter.complete(true);
      await flush();

      expect(downloads.stateOf(1), isA<DownloadDownloaded>());
    });

    test(
      'race: late isCached result does not revert downloaded state',
      () async {
        final downloads = container.read(downloadsStateProvider.notifier);
        // Проверка стартует и ждёт isCachedCompleter.
        final check = downloads.checkStatus(1);
        unawaited(check);

        // Загрузка завершается раньше, чем checkStatus получил результат.
        await downloads.download(_media(1));
        expect(downloads.stateOf(1), isA<DownloadDownloaded>());

        // Поздний ответ isCached == false не должен откатить состояние.
        cache.isCachedCompleter.complete(false);
        await check;
        await flush();

        expect(downloads.stateOf(1), isA<DownloadDownloaded>());
      },
    );
  });

  group('DownloadsStateNotifier.download', () {
    test('повторный старт во время загрузки игнорируется без ошибки', () async {
      final downloads = container.read(downloadsStateProvider.notifier);

      final first = downloads.download(_media(1));
      final second = downloads.download(_media(1));
      await Future.wait([first, second]);

      expect(cache.downloadCalls, 1);
      expect(downloads.stateOf(1), isA<DownloadDownloaded>());
    });

    test('отмена переводит в idle и разрешает рестарт', () async {
      final downloads = container.read(downloadsStateProvider.notifier);

      await downloads.download(_media(2));
      expect(downloads.stateOf(2), isA<DownloadDownloaded>());

      await downloads.cancel(2);
      expect(downloads.stateOf(2), isA<DownloadIdle>());

      await downloads.download(_media(2));
      expect(downloads.stateOf(2), isA<DownloadDownloaded>());
      expect(cache.downloadCalls, 2);
    });

    test('prune выкидывает старые завершённые и они перепроверяются', () async {
      final downloads = container.read(downloadsStateProvider.notifier);

      for (var id = 1; id <= 129; id++) {
        await downloads.download(_media(id));
      }
      final states = container.read(downloadsStateProvider);

      // Лимит 128: самая старая завершённая запись выкинута.
      expect(states.length, 128);
      expect(states.containsKey(1), isFalse);

      // Выкинутый id при следующем показе перепроверяется из кеша,
      // а не висит в «не скачано» навсегда.
      cache.isCachedCompleter.complete(true);
      await downloads.checkStatus(1);
      expect(downloads.stateOf(1), isA<DownloadDownloaded>());
    });
  });

  group('DownloadsStateNotifier.markChecked', () {
    test('множество проверенных не растёт без лимита', () {
      final downloads = container.read(downloadsStateProvider.notifier);

      for (var id = 1; id <= 200; id++) {
        downloads.markChecked(id);
      }
      // Самый старый выкинут и снова считается непроверенным.
      expect(downloads.markChecked(1), isTrue);
      expect(downloads.markChecked(200), isFalse);
    });
  });
}

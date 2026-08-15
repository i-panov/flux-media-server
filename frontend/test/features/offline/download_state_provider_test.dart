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
  _ControllableCache(super.ref, super.baseUrl);

  final Completer<bool> isCachedCompleter = Completer<bool>();

  @override
  Future<bool> isCached(int mediaId) => isCachedCompleter.future;

  @override
  Future<String> download(
    Media media, {
    void Function(int received, int? total)? onProgress,
  }) async {
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

  group('DownloadNotifier.checkStatus', () {
    test('applies cached result when idle', () async {
      // Чтение создаёт сервис и запускает checkStatus.
      final initial = container.read(downloadNotifierProvider(1));
      expect(initial, isA<DownloadIdle>());

      cache.isCachedCompleter.complete(true);
      await flush();

      expect(
        container.read(downloadNotifierProvider(1)),
        isA<DownloadDownloaded>(),
      );
    });

    test('race: late isCached result does not revert downloaded state',
        () async {
      // build запускает checkStatus, который ждёт isCachedCompleter.
      final initial = container.read(downloadNotifierProvider(1));
      expect(initial, isA<DownloadIdle>());

      // Загрузка завершается раньше, чем checkStatus получил результат.
      await container
          .read(downloadNotifierProvider(1).notifier)
          .download(_media(1));
      expect(
        container.read(downloadNotifierProvider(1)),
        isA<DownloadDownloaded>(),
      );

      // Поздний ответ isCached == false не должен откатить состояние.
      cache.isCachedCompleter.complete(false);
      await flush();

      expect(
        container.read(downloadNotifierProvider(1)),
        isA<DownloadDownloaded>(),
      );
    });
  });
}

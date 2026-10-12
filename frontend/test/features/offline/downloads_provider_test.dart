import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _media(int id) => Media(
  id: id,
  title: 'Media $id',
  type: MediaType.audio,
  fileSize: 1,
);

/// Кеш с воротами и сценарными ответами: каждый вызов getCachedMedia
/// возвращает следующий список из [script] (последний повторяется).
class _ScriptedCache extends OfflineCacheService {
  new({required super.prefs}) : super('');

  Completer<void>? gate;
  List<List<Media>> script = const [];
  int calls = 0;

  @override
  Future<List<int>> getCachedIds() async => [1];

  @override
  Future<List<Media>> getCachedMedia() async {
    final data = script[calls < script.length ? calls : script.length - 1];
    calls++;
    final g = gate;
    if (g != null) await g.future;
    return data;
  }
}

void main() {
  late ProviderContainer container;
  late _ScriptedCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    cache = _ScriptedCache(prefs: prefs);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isOfflineProvider.overrideWithValue(true),
        offlineCacheServiceProvider.overrideWith((_) => cache),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('тик инвалидатора во время refresh повторяет загрузку', () async {
    // Первый проход вернёт [1], повторный — [2]: финал доказывает,
    // что второй проход реально отработал, а не потерялся.
    cache
      ..script = [
        [_media(1)],
        [_media(2)],
      ]
      ..gate = Completer<void>();

    container.read(downloadsProvider);
    await flush();
    // Первый refresh висит на воротах.
    expect(cache.calls, 1);

    // Тик посреди refresh: раньше терялся (return при _isRefreshing),
    // теперь ставит dirty-флаг.
    container.read(downloadsInvalidatorProvider.notifier).state++;
    await flush();
    expect(cache.calls, 1);

    cache.gate!.complete();
    await flush();

    expect(cache.calls, 2);
    expect(
      container.read(downloadsProvider).value!.map((m) => m.id),
      [2],
    );
  });

  test('без тиков посреди refresh второго прохода нет', () async {
    cache.script = [
      [_media(1)],
    ];

    container.read(downloadsProvider);
    await flush();

    expect(cache.calls, 1);
    expect(
      container.read(downloadsProvider).value!.map((m) => m.id),
      [1],
    );
  });
}

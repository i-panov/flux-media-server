import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

class DownloadsNotifier extends Notifier<AsyncValue<List<Media>>> {
  /// Защита от параллельных refresh (тики инвалидатора могут прийти
  /// подряд).
  bool _isRefreshing = false;

  @override
  AsyncValue<List<Media>> build() {
    // Watch the invalidator counter — refresh whenever it changes.
    ref.listen<int>(downloadsInvalidatorProvider, (_, next) {
      refresh();
    });
    // Первый refresh откладываем: внутри refresh читается `state`,
    // а до завершения build() обращение к нему запрещено.
    Future.microtask(refresh);
    return const AsyncValue.loading();
  }

  /// Reloads the list of downloaded media.
  /// In offline mode reads locally stored JSON metadata (no API calls).
  /// In online mode fetches fresh data from the API.
  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    // Фоновая перезагрузка: при уже загруженных данных не ставим
    // loading (иначе секция мигает на каждый тик инвалидатора).
    final hasData = state.hasValue;
    if (!hasData) {
      state = const AsyncValue.loading();
    }
    try {
      final cacheService = ref.read(offlineCacheServiceProvider);
      final isOffline = ref.read(isOfflineProvider);

      if (isOffline) {
        // Offline: read locally cached metadata only.
        final mediaList = await cacheService.getCachedMedia();
        state = AsyncValue.data(mediaList);
        return;
      }

      // Online: try API first, fall back to local metadata on failure.
      final ids = await cacheService.getCachedIds();
      if (ids.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      // Закешированные треки берём из локальных метаданных без GET
      // (кеш хранит Media); запросы идут только для отсутствующих.
      final cachedById = <int, Media>{
        for (final m in await cacheService.getCachedMedia()) m.id: m,
      };
      final missingIds =
          ids.where((id) => !cachedById.containsKey(id)).toList();

      final mediaRepository = ref.read(mediaRepositoryProvider);
      // Один bulk-запрос вместо N+1 (лимит сервера — 100 id на запрос,
      // порции по 8 дольше не нужны). Поштучный фолбэк — только если
      // bulk-запрос упал целиком.
      const bulkLimit = 100;
      final fetchedById = <int, Media>{};
      var allFailed = missingIds.isNotEmpty;
      for (var i = 0; i < missingIds.length; i += bulkLimit) {
        final end = (i + bulkLimit < missingIds.length)
            ? i + bulkLimit
            : missingIds.length;
        final chunk = missingIds.sublist(i, end);

        final bulkResult = await mediaRepository.getMediaBulk(chunk);
        final bulkFailed = bulkResult.isLeft();
        if (bulkFailed) {
          // Bulk недоступен (старый сервер или сбой) — поштучно.
          for (final id in chunk) {
            final detail = await mediaRepository.getMediaDetail(id);
            detail.fold(
              (failure) => null,
              (media) {
                fetchedById[media.id] = media;
                allFailed = false;
                // Persist metadata for offline access.
                cacheService.saveMetadata(media);
              },
            );
          }
          continue;
        }
        for (final media
            in bulkResult.getRight().toNullable() ?? const <Media>[]) {
          fetchedById[media.id] = media;
          allFailed = false;
          // Persist metadata for offline access.
          unawaited(cacheService.saveMetadata(media));
        }
      }

      final mediaList = <Media>[];
      for (final id in ids) {
        final media = cachedById[id] ?? fetchedById[id];
        if (media != null) mediaList.add(media);
      }

      if (mediaList.isEmpty && allFailed) {
        // All API calls failed and no cached metadata — fall back to local.
        final localMedia = await cacheService.getCachedMedia();
        state = AsyncValue.data(localMedia);
      } else {
        state = AsyncValue.data(mediaList);
      }
    } catch (e, st) {
      // При фоновой перезагрузке старые данные сохраняем как есть.
      if (hasData) return;
      // Last resort: try local metadata.
      try {
        final cacheService = ref.read(offlineCacheServiceProvider);
        final localMedia = await cacheService.getCachedMedia();
        if (localMedia.isNotEmpty) {
          state = AsyncValue.data(localMedia);
          return;
        }
      } catch (_) {}
      state = AsyncValue.error(e, st);
    } finally {
      _isRefreshing = false;
    }
  }
}

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, AsyncValue<List<Media>>>(
  DownloadsNotifier.new,
);

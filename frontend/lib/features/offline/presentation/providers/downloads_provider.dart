import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

class DownloadsNotifier extends StateNotifier<AsyncValue<List<Media>>> {
  DownloadsNotifier(this._ref)
      : super(const AsyncValue.loading()) {
    // Watch the invalidator counter — refresh whenever it changes.
    _ref.listen<int>(downloadsInvalidatorProvider, (_, next) {
      refresh();
    });
    refresh();
  }

  final Ref _ref;

  /// Reloads the list of downloaded media.
  /// In offline mode reads locally stored JSON metadata (no API calls).
  /// In online mode fetches fresh data from the API.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final cacheService = _ref.read(offlineCacheServiceProvider);
      final isOffline = _ref.read(isOfflineProvider);

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

      final mediaRepository = _ref.read(mediaRepositoryProvider);
      final futures = ids.map((id) => mediaRepository.getMediaDetail(id));
      final results = await Future.wait(futures);

      final mediaList = <Media>[];
      var allFailed = true;
      for (final result in results) {
        result.fold(
          (failure) => null,
          (media) {
            mediaList.add(media);
            allFailed = false;
            // Persist metadata for offline access.
            cacheService.saveMetadata(media);
          },
        );
      }

      if (allFailed && mediaList.isEmpty) {
        // All API calls failed — fall back to local metadata.
        final localMedia = await cacheService.getCachedMedia();
        state = AsyncValue.data(localMedia);
      } else {
        state = AsyncValue.data(mediaList);
      }
    } catch (e, st) {
      // Last resort: try local metadata.
      try {
        final cacheService = _ref.read(offlineCacheServiceProvider);
        final localMedia = await cacheService.getCachedMedia();
        if (localMedia.isNotEmpty) {
          state = AsyncValue.data(localMedia);
          return;
        }
      } catch (_) {}
      state = AsyncValue.error(e, st);
    }
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, AsyncValue<List<Media>>>((ref) {
  return DownloadsNotifier(ref);
});

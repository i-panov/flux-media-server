import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Reloads the list of downloaded media from disk + API.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final cacheService = _ref.read(offlineCacheServiceProvider);
      final mediaRepository = _ref.read(mediaRepositoryProvider);
      final ids = await cacheService.getCachedIds();
      if (ids.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      // Parallel fetch instead of sequential N+1 queries
      final futures = ids.map((id) => mediaRepository.getMediaDetail(id));
      final results = await Future.wait(futures);

      final mediaList = <Media>[];
      for (final result in results) {
        result.fold(
          (failure) => null,
          (media) => mediaList.add(media),
        );
      }
      state = AsyncValue.data(mediaList);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, AsyncValue<List<Media>>>((ref) {
  return DownloadsNotifier(ref);
});

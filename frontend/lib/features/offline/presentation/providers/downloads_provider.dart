import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/media.dart';

final downloadsProvider = FutureProvider<List<Media>>((ref) async {
  final cacheService = ref.watch(offlineCacheServiceProvider);
  final mediaRepository = ref.watch(mediaRepositoryProvider);
  final ids = await cacheService.getCachedIds();
  if (ids.isEmpty) return [];

  // Parallel fetch instead of sequential N+1 queries
  final futures = ids.map((id) => mediaRepository.getMediaDetail(id));
  final results = await Future.wait(futures);

  final mediaList = <Media>[];
  for (final result in results) {
    result.fold(
      (_) {},
      (media) => mediaList.add(media),
    );
  }
  return mediaList;
});

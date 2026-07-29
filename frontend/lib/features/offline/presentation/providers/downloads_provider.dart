import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/media.dart';

final downloadsProvider = FutureProvider<List<Media>>((ref) async {
  final cacheService = ref.watch(offlineCacheServiceProvider);
  final mediaRepository = ref.watch(mediaRepositoryProvider);
  final ids = await cacheService.getCachedIds();
  if (ids.isEmpty) return [];
  final results = <Media>[];
  for (final id in ids) {
    final result = await mediaRepository.getMediaDetail(id);
    result.fold(
      (_) {},
      (media) => results.add(media),
    );
  }
  return results;
});

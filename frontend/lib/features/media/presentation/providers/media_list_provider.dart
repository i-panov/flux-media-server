import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

class MediaListResult {
  const MediaListResult({required this.items, required this.total});

  final List<Media> items;
  final int total;
}

final mediaRemoteDataSourceProvider = Provider<MediaRemoteDataSource>((ref) {
  return MediaRemoteDataSource(ref.watch(apiClientProvider));
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepositoryImpl(ref.watch(mediaRemoteDataSourceProvider));
});

final mediaListProvider = AsyncNotifierProvider<MediaListNotifier, MediaListResult>(MediaListNotifier.new);

class MediaListNotifier extends AsyncNotifier<MediaListResult> {
  static const _pageSize = 20;

  @override
  Future<MediaListResult> build() async {
    final repo = ref.watch(mediaRepositoryProvider);
    final result = await repo.getMediaList(limit: _pageSize, offset: 0);
    return result.fold(
      (failure) => throw Exception(failure.message),
      (data) => MediaListResult(items: data.items, total: data.total),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.items.length >= current.total) return;
    final repo = ref.read(mediaRepositoryProvider);
    final result = await repo.getMediaList(
      limit: _pageSize,
      offset: current.items.length,
    );
    result.fold(
      (failure) => state = AsyncError(Exception(failure.message), StackTrace.current),
      (data) => state = AsyncValue.data(
        MediaListResult(
          items: [...current.items, ...data.items],
          total: data.total,
        ),
      ),
    );
  }
}

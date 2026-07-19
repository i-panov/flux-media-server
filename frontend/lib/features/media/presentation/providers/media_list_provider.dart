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

/// Current search query. Empty string means no search.
final searchQueryProvider = StateProvider<String>((ref) => '');

final mediaListProvider = AsyncNotifierProvider<MediaListNotifier, MediaListResult>(MediaListNotifier.new);

class MediaListNotifier extends AsyncNotifier<MediaListResult> {
  static const _pageSize = 20;

  @override
  Future<MediaListResult> build() async {
    final repo = ref.watch(mediaRepositoryProvider);
    final q = ref.watch(searchQueryProvider);
    final result = await repo.getMediaList(
      limit: _pageSize,
      offset: 0,
      q: q.isEmpty ? null : q,
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (data) => MediaListResult(items: data.items, total: data.total),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.items.length >= current.total) return;
    final repo = ref.read(mediaRepositoryProvider);
    final q = ref.read(searchQueryProvider);
    final result = await repo.getMediaList(
      limit: _pageSize,
      offset: current.items.length,
      q: q.isEmpty ? null : q,
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

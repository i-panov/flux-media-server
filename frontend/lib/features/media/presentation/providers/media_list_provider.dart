import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/check_media_hash.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_list.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_media.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_cover.dart';
import 'package:flux_media_server/shared/models/media.dart';

class MediaListResult {
  const MediaListResult({required this.items, required this.total});

  final IList<Media> items;
  final int total;
}

final mediaRemoteDataSourceProvider = Provider<MediaRemoteDataSource>((ref) {
  return MediaRemoteDataSource(ref.watch(apiClientProvider));
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepositoryImpl(ref.watch(mediaRemoteDataSourceProvider));
});

final getMediaListProvider = Provider<GetMediaList>((ref) {
  return GetMediaList(ref.watch(mediaRepositoryProvider));
});

final checkMediaHashProvider = Provider<CheckMediaHash>((ref) {
  return CheckMediaHash(ref.watch(mediaRepositoryProvider));
});

final uploadMediaProvider = Provider<UploadMedia>((ref) {
  return UploadMedia(ref.watch(mediaRepositoryProvider));
});

final uploadCoverProvider = Provider<UploadCover>((ref) {
  return UploadCover(ref.watch(mediaRepositoryProvider));
});

/// Current search query. Empty string means no search.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Media list scoped to a media type ('video' or 'audio').
/// Using a family avoids state leakage between audio/video tabs that
/// previously shared a single global [mediaListProvider].
final mediaListProvider =
    AsyncNotifierProvider.family<MediaListNotifier, MediaListResult, String>(
  MediaListNotifier.new,
);

class MediaListNotifier extends FamilyAsyncNotifier<MediaListResult, String> {
  static const _pageSize = 20;

  @override
  Future<MediaListResult> build(String type) async {
    final getMediaList = ref.watch(getMediaListProvider);
    final q = ref.watch(searchQueryProvider);
    final result = await getMediaList(
      GetMediaListParams(
        limit: _pageSize,
        offset: 0,
        q: q.isEmpty ? null : q,
        type: type,
      ),
    );
    return result.fold(
      (failure) => throw Exception(failure.message),
      (data) => MediaListResult(
        items: data.items.toIList(),
        total: data.total,
      ),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.items.length >= current.total) return;
    final getMediaList = ref.read(getMediaListProvider);
    final q = ref.read(searchQueryProvider);
    final result = await getMediaList(
      GetMediaListParams(
        limit: _pageSize,
        offset: current.items.length,
        q: q.isEmpty ? null : q,
        type: arg,
      ),
    );
    result.fold(
      (failure) => state = AsyncError(Exception(failure.message), StackTrace.current),
      (data) => state = AsyncValue.data(
        MediaListResult(
          items: current.items.addAll(data.items),
          total: data.total,
        ),
      ),
    );
  }
}

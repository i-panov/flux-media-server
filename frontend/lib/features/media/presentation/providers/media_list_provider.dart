import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/domain/usecases/cancel_upload.dart';
import 'package:flux_media_server/features/media/domain/usecases/check_media_hash.dart';
import 'package:flux_media_server/features/media/domain/usecases/delete_media.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_artists.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_list.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_upload_status.dart';
import 'package:flux_media_server/features/media/domain/usecases/update_metadata.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_cover.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_media.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Инвалидирует списки медиа обоих типов после мутаций (загрузка,
/// удаление, смена обложки, редактирование метаданных).
void refreshMediaLists(WidgetRef ref) {
  ref
    ..invalidate(mediaListProvider('video'))
    ..invalidate(mediaListProvider('audio'));
}

class MediaListResult {
  const MediaListResult({required this.items, required this.total});

  final IList<Media> items;
  final int total;
}

final mediaRemoteDataSourceProvider = Provider<MediaRemoteDataSource>((ref) {
  return MediaRemoteDataSource(
    ref.watch(mediaApiClientProvider),
    libraryApiClient: ref.watch(libraryApiClientProvider),
    uploadBaseUrl: ref.watch(baseUrlProvider),
    authToken: () => ref.read(settingsProvider).settings.authToken,
    refreshAuth: () async {
      final refreshToken = ref.read(settingsProvider).settings.refreshToken;
      if (refreshToken == null) return null;
      final refreshed =
          await ref.read(authTokenRefresherProvider).refresh(refreshToken);
      return refreshed
          ? ref.read(settingsProvider).settings.authToken
          : null;
    },
  );
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepositoryImpl(ref.watch(mediaRemoteDataSourceProvider));
});

final getMediaListProvider = Provider<GetMediaList>((ref) {
  return GetMediaList(ref.watch(mediaRepositoryProvider));
});

final getArtistsProvider = Provider<GetArtists>((ref) {
  return GetArtists(ref.watch(mediaRepositoryProvider));
});

final checkMediaHashProvider = Provider<CheckMediaHash>((ref) {
  return CheckMediaHash(ref.watch(mediaRepositoryProvider));
});

final uploadMediaProvider = Provider<UploadMedia>((ref) {
  return UploadMedia(ref.watch(mediaRepositoryProvider));
});

final getUploadStatusProvider = Provider<GetUploadStatus>((ref) {
  return GetUploadStatus(ref.watch(mediaRepositoryProvider));
});

final cancelUploadProvider = Provider<CancelUpload>((ref) {
  return CancelUpload(ref.watch(mediaRepositoryProvider));
});

final uploadCoverProvider = Provider<UploadCover>((ref) {
  return UploadCover(ref.watch(mediaRepositoryProvider));
});

final deleteMediaProvider = Provider<DeleteMedia>((ref) {
  return DeleteMedia(ref.watch(mediaRepositoryProvider));
});

final updateMetadataProvider = Provider<UpdateMetadata>((ref) {
  return UpdateMetadata(ref.watch(mediaRepositoryProvider));
});

/// Current search query scoped to a media type ('video' or 'audio').
/// Using a family avoids state leakage between audio/video tabs.
final searchQueryProvider =
    StateProvider.family<String, String>((ref, type) => '');

/// Media list scoped to a media type ('video' or 'audio').
/// Using a family avoids state leakage between audio/video tabs that
/// previously shared a single global [mediaListProvider].
final mediaListProvider =
    AsyncNotifierProvider.family<MediaListNotifier, MediaListResult, String>(
  MediaListNotifier.new,
);

class MediaListNotifier extends FamilyAsyncNotifier<MediaListResult, String> {
  static const _pageSize = 20;

  bool _isLoadingMore = false;

  @override
  Future<MediaListResult> build(String type) async {
    // Смена query (или тип) пересоздаёт список: сбрасываем флаг,
    // иначе незавершённый loadMore заблокирует подгрузку нового списка.
    _isLoadingMore = false;

    final getMediaList = ref.watch(getMediaListProvider);
    final q = ref.watch(searchQueryProvider(type));
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

  /// Loads the next page of results.
  ///
  /// Guards against concurrent calls and stale query results:
  /// - [_isLoadingMore] prevents duplicate requests with the same offset.
  /// - Captures the query at call time and compares against the latest
  ///   value after the async request completes; if the query changed, the
  ///   result is discarded to avoid appending items from a previous search.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.items.length >= current.total) return;
    if (_isLoadingMore) return;

    // Capture the query at call time.
    final qAtCall = ref.read(searchQueryProvider(arg));
    _isLoadingMore = true;

    final getMediaList = ref.read(getMediaListProvider);
    final result = await getMediaList(
      GetMediaListParams(
        limit: _pageSize,
        offset: current.items.length,
        q: qAtCall.isEmpty ? null : qAtCall,
        type: arg,
      ),
    );

    _isLoadingMore = false;

    // If the query changed during the async request, discard the result.
    final qNow = ref.read(searchQueryProvider(arg));
    if (qNow != qAtCall) return;

    result.fold(
      (failure) {
        // Данные сохраняем, но ошибку показываем: без `AsyncValue.error`
        // copyWithPrevious — no-op, и пользователь не узнал бы о провале.
        state = AsyncValue<MediaListResult>.error(
          Exception(failure.message),
          StackTrace.current,
        ).copyWithPrevious(state);
      },
      (data) => state = AsyncValue.data(
        MediaListResult(
          items: current.items.addAll(data.items),
          total: data.total,
        ),
      ),
    );
  }
}

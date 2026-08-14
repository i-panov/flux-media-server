import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_detail.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_detail_provider.freezed.dart';

@freezed
class MediaDetailState with _$MediaDetailState {
  const factory MediaDetailState.loading() = MediaDetailLoading;
  const factory MediaDetailState.loaded({required Media media}) =
      MediaDetailLoaded;
  const factory MediaDetailState.error({required String message}) =
      MediaDetailError;
}

class MediaDetailNotifier extends StateNotifier<MediaDetailState> {
  MediaDetailNotifier({
    required GetMediaDetail getMediaDetail,
    required Ref ref,
  })  : _getMediaDetail = getMediaDetail,
        _ref = ref,
        super(const MediaDetailState.loading());

  final GetMediaDetail _getMediaDetail;
  final Ref _ref;

  Future<void> load(int id) async {
    state = const MediaDetailState.loading();
    final result = await _getMediaDetail(id);
    await result.fold<Future<void>>(
      (failure) async {
        // API failed — try local metadata (offline mode).
        final cacheService = _ref.read(offlineCacheServiceProvider);
        final cachedMedia = await cacheService.getCachedMedia();
        final local = cachedMedia.where((m) => m.id == id).firstOrNull;
        if (local != null) {
          state = MediaDetailState.loaded(media: local);
        } else {
          state = MediaDetailState.error(message: failure.message);
        }
      },
      (media) async {
        // Persist metadata for offline access.
        unawaited(
          _ref.read(offlineCacheServiceProvider).saveMetadata(media),
        );
        state = MediaDetailState.loaded(media: media);
      },
    );
  }

  void updateMedia(Media media) {
    state = MediaDetailState.loaded(media: media);
  }

  /// Точечно обновляет обложку без перевода экрана в loading.
  ///
  /// [coverUrl] используется как флаг наличия обложки; обновление
  /// `updatedAt` меняет cache-buster в URL картинки, чтобы обновилась
  /// картинка.
  void setCoverUrl(String coverUrl) {
    state = state.maybeWhen(
      loaded: (media) => MediaDetailState.loaded(
        media: media.copyWith(
          coverUrl: coverUrl,
          updatedAt: DateTime.now(),
        ),
      ),
      orElse: () => state,
    );
  }
}

final getMediaDetailUseCaseProvider = Provider<GetMediaDetail>((ref) {
  return GetMediaDetail(ref.watch(mediaRepositoryProvider));
});

final mediaDetailProvider = StateNotifierProvider.autoDispose
    .family<MediaDetailNotifier, MediaDetailState, int>(
  (ref, mediaId) => MediaDetailNotifier(
    getMediaDetail: ref.watch(getMediaDetailUseCaseProvider),
    ref: ref,
  ),
);

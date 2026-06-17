import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_detail.dart';
import 'package:flux_media_server/shared/models/media.dart';

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
  MediaDetailNotifier({required GetMediaDetail getMediaDetail})
      : _getMediaDetail = getMediaDetail,
        super(const MediaDetailState.loading());

  final GetMediaDetail _getMediaDetail;

  Future<void> load(int id) async {
    state = const MediaDetailState.loading();
    final result = await _getMediaDetail(id);
    result.fold(
      (failure) => state = MediaDetailState.error(message: failure.message),
      (media) => state = MediaDetailState.loaded(media: media),
    );
  }
}

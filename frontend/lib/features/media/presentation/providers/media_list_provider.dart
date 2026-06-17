import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/utils/either.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_list.dart';
import 'package:flux_media_server/shared/models/media.dart';

part 'media_list_provider.freezed.dart';

@freezed
class MediaListState with _$MediaListState {
  const factory MediaListState.loading() = MediaListLoading;
  const factory MediaListState.loaded({
    required List<Media> items,
    required int total,
    required bool hasReachedMax,
  }) = MediaListLoaded;
  const factory MediaListState.error({required String message}) = MediaListError;
}

class MediaListNotifier extends StateNotifier<MediaListState> {
  MediaListNotifier({
    required GetMediaList getMediaList,
    String? type,
    int? year,
  })  : _getMediaList = getMediaList,
        _type = type,
        _year = year,
        super(const MediaListState.loading());

  final GetMediaList _getMediaList;
  final String? _type;
  final int? _year;
  static const _pageSize = 20;

  Future<void> load() async {
    state = const MediaListState.loading();
    final result = await _getMediaList(
      GetMediaListParams(type: _type, year: _year, limit: _pageSize, offset: 0),
    );
    result.fold(
      (failure) => state = MediaListState.error(message: failure.message),
      (data) => state = MediaListState.loaded(
        items: data.items,
        total: data.total,
        hasReachedMax: data.items.length >= data.total,
      ),
    );
  }

  Future<void> loadMore() async {
    final currentState = state;
    if (currentState is! MediaListLoaded || currentState.hasReachedMax) return;

    final offset = currentState.items.length;
    final result = await _getMediaList(
      GetMediaListParams(
        type: _type,
        year: _year,
        limit: _pageSize,
        offset: offset,
      ),
    );
    result.fold(
      (failure) => state = MediaListState.error(message: failure.message),
      (data) => state = MediaListState.loaded(
        items: [...currentState.items, ...data.items],
        total: data.total,
        hasReachedMax: offset + data.items.length >= data.total,
      ),
    );
  }
}

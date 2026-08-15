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

class MediaDetailNotifier
    extends AutoDisposeFamilyNotifier<MediaDetailState, int> {
  late final GetMediaDetail _getMediaDetail;

  /// Замена `mounted` из StateNotifier: нотифаер может быть автоутилизирован
  /// во время полёта запроса (уход с экрана).
  bool _disposed = false;

  @override
  MediaDetailState build(int mediaId) {
    _getMediaDetail = ref.watch(getMediaDetailUseCaseProvider);
    ref.onDispose(() => _disposed = true);
    // Первичную загрузку запускаем из build(): Notifier запрещает
    // модификацию состояния, если провайдер создан и изменён в фазе
    // построения виджета (вызов load() из initState экрана падал бы с
    // "Tried to modify a provider while the widget tree was building").
    Future.microtask(() => load(mediaId));
    return const MediaDetailState.loading();
  }

  /// Поколение запроса: повторный Retry не должен давать гонку, когда
  /// старый ответ перезаписывает свежий. Ответ устаревшего поколения
  /// отбрасывается.
  int _generation = 0;

  Future<void> load(int id) async {
    if (_disposed) return;
    final generation = ++_generation;
    state = const MediaDetailState.loading();
    final result = await _getMediaDetail(id);
    if (_disposed || generation != _generation) return;
    await result.fold<Future<void>>(
      (failure) async {
        // API failed — try local metadata (offline mode).
        final cacheService = ref.read(offlineCacheServiceProvider);
        final cachedMedia = await cacheService.getCachedMedia();
        if (_disposed || generation != _generation) return;
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
          ref.read(offlineCacheServiceProvider).saveMetadata(media),
        );
        if (_disposed || generation != _generation) return;
        state = MediaDetailState.loaded(media: media);
      },
    );
  }

  void updateMedia(Media media) {
    state = MediaDetailState.loaded(media: media);
  }

  /// Тихий перезапрос с сервера: экран не переводится в loading.
  ///
  /// Используется после загрузки обложки: серверный `updatedAt` даёт
  /// честный cache-buster для картинки (клиентское время в setCoverUrl
  /// врало бы его).
  Future<void> refresh() async {
    final current = state;
    if (current is! MediaDetailLoaded) return;
    final generation = ++_generation;
    final result = await _getMediaDetail(current.media.id);
    if (_disposed || generation != _generation) return;
    result.fold(
      (failure) {
        // Молча: обложка уже загружена, старое состояние тоже валидно.
      },
      (media) {
        unawaited(
          ref.read(offlineCacheServiceProvider).saveMetadata(media),
        );
        if (_disposed || generation != _generation) return;
        state = MediaDetailState.loaded(media: media);
      },
    );
  }
}

final getMediaDetailUseCaseProvider = Provider<GetMediaDetail>((ref) {
  return GetMediaDetail(ref.watch(mediaRepositoryProvider));
});

final mediaDetailProvider = NotifierProvider.autoDispose
    .family<MediaDetailNotifier, MediaDetailState, int>(
  MediaDetailNotifier.new,
);

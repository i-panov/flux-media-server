import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Аудиотрек, извлечённый из видео [mediaId] (null — связки нет).
/// Экран видео по нему решает: кнопка «перейти к треку» вместо «извлечь».
final extractedAudioProvider = FutureProvider.family<Media?, int>((
  ref,
  mediaId,
) async {
  final result = await ref
      .watch(mediaRepositoryProvider)
      .getExtractedAudio(mediaId);
  return await result.fold(
    // Тип Failure сохраняется в AsyncError (паттерн остальных провайдеров).
    // ignore: only_throw_errors
    (failure) => throw failure,
    (media) => media,
  );
});

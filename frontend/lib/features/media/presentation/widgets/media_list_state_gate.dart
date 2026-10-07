import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';

/// Развилка «список / загрузка / ошибка» для экранов медиа.
///
/// Копия стояла в `audio_screen` и `artist_page` и разошлась: `artist_page`
/// проверял `isLoading`, из-за чего pull-to-refresh гасил содержимое экрана
/// (у `AsyncLoading` с сохранённым `value` данные есть, прятать их не надо).
/// Здесь принято поведение `audio_screen` — заглушка только когда данных
/// ещё нет.
///
/// Возвращает виджет-заглушку или `null`, если экран должен рисовать
/// содержимое сам.
Widget? mediaListStateGate(
  WidgetRef ref, {
  required String mediaType,
  required bool favoritesHasError,
  required bool favoritesLoading,
  required VoidCallback onRetry,
}) {
  final mediaList = ref.watch(mediaListProvider(mediaType));
  if (mediaList.hasError || favoritesHasError) {
    return ErrorRetryView(
      message:
          mediaList.error?.toString() ??
          ref.watch(favoritesProvider).error?.toString(),
      onRetry: onRetry,
    );
  }
  if (mediaList.value == null || favoritesLoading) {
    return const Center(child: CircularProgressIndicator());
  }
  return null;
}

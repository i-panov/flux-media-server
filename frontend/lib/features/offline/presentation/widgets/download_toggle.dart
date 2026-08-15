import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Общий хелпер переключения загрузки трека/видео: скачать или удалить.
///
/// Дублировался в audio_screen, artist_page и video_screen.
Future<void> toggleDownload(
  WidgetRef ref, {
  required int mediaId,
  required String mediaType,
}) async {
  final downloadState = ref.read(downloadNotifierProvider(mediaId));
  if (downloadState is DownloadDownloaded) {
    await ref.read(downloadNotifierProvider(mediaId).notifier).remove(mediaId);
  } else if (downloadState is DownloadDownloading) {
    // Повторный тап во время загрузки отменяет её.
    await ref.read(downloadNotifierProvider(mediaId).notifier).cancel(mediaId);
  } else {
    var media = _findInLoadedPages(ref, mediaId, mediaType);
    if (media == null) {
      // Трек вне загруженных страниц пагинации — берём детали с сервера.
      final result =
          await ref.read(mediaRepositoryProvider).getMediaDetail(mediaId);
      media = result.fold((_) => null, (m) => m);
    }
    // Фолбэк-заглушки больше нет: без реальных метаданных не скачиваем,
    // иначе в кеш попадут пустые записи.
    if (media == null) return;
    await ref.read(downloadNotifierProvider(mediaId).notifier).download(media);
  }
}

Media? _findInLoadedPages(WidgetRef ref, int mediaId, String mediaType) {
  final mediaList = ref.read(mediaListProvider(mediaType)).valueOrNull;
  if (mediaList == null) return null;
  for (final m in mediaList.items) {
    if (m.id == mediaId) return m;
  }
  return null;
}

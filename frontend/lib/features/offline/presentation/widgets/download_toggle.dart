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
    final mediaList = ref.read(mediaListProvider(mediaType)).valueOrNull;
    if (mediaList != null) {
      final media = mediaList.items.firstWhere(
        (m) => m.id == mediaId,
        orElse: () => Media(
          id: mediaId,
          title: '',
          type: mediaType == MediaType.audio.value
              ? MediaType.audio
              : MediaType.video,
          fileSize: 0,
        ),
      );
      await ref
          .read(downloadNotifierProvider(mediaId).notifier)
          .download(media);
    }
  }
}

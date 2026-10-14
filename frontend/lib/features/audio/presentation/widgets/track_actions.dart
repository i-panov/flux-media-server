import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/download_toggle.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/save_to_files.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Общие действия с треком для экранов audio/video:
/// избранное, скачивание и добавление в очередь (раньше — три копии).
///
/// Расширения вместо миксинов: `WidgetRef` и так доступен везде, где
/// нужны эти действия, поэтому таскать его параметром через 27 вызовов
/// (и держать два параллельных миксина под State/Widget) незачем.
extension TrackActionsX on WidgetRef {
  void toggleFavoriteTrack(int mediaId) {
    unawaited(read(favoriteToggleProvider(mediaId).notifier).toggle());
  }

  Future<void> toggleDownloadTrack(String mediaType, int mediaId) {
    return toggleDownload(this, mediaId: mediaId, mediaType: mediaType);
  }
}

/// Добавление в очередь — отдельно: нужен ещё `context` для снекбара
/// и `mounted`-проверка, которых у голого `WidgetRef` нет.
extension ConsumerTrackActions<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  void addTrackToQueue(Media media) {
    ref.read(playQueueProvider.notifier).enqueue(media);
    // enqueue синхронный, await между ним и снекбаром нет — но вызов мог
    // прийти из уже размонтированного контекста (колбэк диалога,
    // отложенный тап), тогда showTextSnackBar бросит на деактивированном
    // виджете. Проверяем текущее состояние, а не «пока ждали».
    if (!mounted) return;
    showTextSnackBar(context, context.l10n.addedToQueue);
  }

  /// Сохранение трека в файлы — здесь же: нужны `context` (диалог выбора
  /// места, локализация) и `mounted`-проверка после await.
  Future<void> saveTrackToFiles(String mediaType, int mediaId) async {
    final media = await resolveMediaForExport(ref, mediaId, mediaType);
    if (!mounted) return;
    if (media == null) return;
    await saveMediaToFiles(context, ref, media);
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/download_toggle.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Общие действия с треком для экранов audio/video:
/// избранное, скачивание и добавление в очередь (раньше — три копии).
///
/// `WidgetRef` передаётся параметром: у [_TrackActionsRef] нет доступа к
/// `ref` извнутри, а у State-версии он есть — поэтому два миксина.
mixin TrackActionsMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  void toggleFavoriteTrack(WidgetRef ref, int mediaId) {
    unawaited(ref.read(favoriteToggleProvider(mediaId).notifier).toggle());
  }

  Future<void> toggleDownloadTrack(
    WidgetRef ref,
    String mediaType,
    int mediaId,
  ) {
    return toggleDownload(ref, mediaId: mediaId, mediaType: mediaType);
  }

  void addTrackToQueue(WidgetRef ref, Media media) {
    ref.read(playQueueProvider.notifier).enqueue(media);
    // Экран мог размонтироваться пока ждали реакцию очереди: иначе
    // ScaffoldMessenger.of(context) бросил бы на деактивированном
    // виджете. `ref` проверяем, а не `mounted` — миксин не знает,
    // успел ли экран уйти.
    if (!mounted) return;
    showTextSnackBar(context, context.l10n.addedToQueue);
  }
}

/// Действия с треком для виджетов без состояния.
mixin TrackActionsRef on ConsumerWidget {
  void toggleFavoriteTrack(WidgetRef ref, int mediaId) {
    unawaited(ref.read(favoriteToggleProvider(mediaId).notifier).toggle());
  }

  Future<void> toggleDownloadTrack(
    WidgetRef ref,
    String mediaType,
    int mediaId,
  ) => toggleDownload(ref, mediaId: mediaId, mediaType: mediaType);
}

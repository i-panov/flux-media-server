import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/download_toggle.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Общие действия с треком для экранов audio/video:
/// избранное, скачивание и добавление в очередь (раньше — три копии).
mixin TrackActionsMixin<T extends StatefulWidget> on State<T> {
  void toggleFavoriteTrack(WidgetRef ref, int mediaId) {
    ref.read(favoriteToggleProvider(mediaId).notifier).toggle();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.addedToQueue)),
    );
  }
}

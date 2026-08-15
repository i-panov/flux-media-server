import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/widgets/audio_placeholder.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Flat track row for audio listings with cover, title, artist, and actions.
/// Tap on cover starts/pauses playback; long-press opens the detail page.
class AudioTrackRow extends ConsumerWidget {
  const AudioTrackRow({
    required this.media,
    super.key,
    this.isFavorite = false,
    this.onPlay,
    this.onFavorite,
    this.onDownload,
    this.onAddToQueue,
    this.onAddToCollection,
    this.onEditMetadata,
    this.onDetails,
  });

  final Media media;
  final bool isFavorite;
  final VoidCallback? onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onDownload;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onEditMetadata;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(baseUrlProvider);
    final hasCover =
        (media.coverUrl?.isNotEmpty ?? false) ||
        (media.thumbnailUrl?.isNotEmpty ?? false);
    final cacheBuster = media.updatedAt?.millisecondsSinceEpoch;
    final buster = cacheBuster != null ? '?v=$cacheBuster' : '';
    final imageUrl = hasCover
        ? '$baseUrl/media/${media.id}/cover$buster'
        : '$baseUrl/media/${media.id}/thumb$buster';
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    final downloadState = ref.watch(downloadNotifierProvider(media.id));
    final isDownloaded = downloadState is DownloadDownloaded;
    final isDownloading = downloadState is DownloadDownloading;
    final downloadProgress = switch (downloadState) {
      DownloadDownloading(:final progress) => progress,
      _ => 0.0,
    };

    // select: тики позиции не должны перестраивать все ряды — нужны
    // только текущий mediaId и состояние паузы.
    final playback = ref.watch(
      playbackCoordinatorProvider.select((state) {
        return switch (state) {
          PlaybackPlaying(:final media, :final isPaused) => (
              mediaId: media.id,
              isPaused: isPaused,
            ),
          _ => null,
        };
      }),
    );
    final isCurrentlyPlaying = playback?.mediaId == media.id;
    final isCurrentlyPaused =
        (playback?.isPaused ?? false) && isCurrentlyPlaying;

    return InkWell(
      onTap: onPlay,
      onLongPress: onDetails,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: isCurrentlyPlaying
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // Cover — tap toggles play/pause
            GestureDetector(
              onTap: () {
                final p = playback;
                if (p != null && p.mediaId == media.id) {
                  if (p.isPaused) {
                    ref.read(playbackCoordinatorProvider.notifier).resume();
                  } else {
                    ref.read(playbackCoordinatorProvider.notifier).pause();
                  }
                } else {
                  onPlay?.call();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: isCurrentlyPlaying
                      ? ColoredBox(
                          color: colorScheme.primaryContainer,
                          child: Icon(
                            // Индикатор паузы на обложке текущего трека.
                            isCurrentlyPaused
                                ? Icons.pause
                                : Icons.equalizer,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                        )
                      : hasCover
                          ? AuthNetworkImage(
                              imageUrl: imageUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => ColoredBox(
                                color: colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.music_note,
                                  color: colorScheme.primary,
                                  size: 24,
                                ),
                              ),
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.music_note,
                                  color: colorScheme.primary,
                                  size: 24,
                                ),
                              ),
                            )
                          : const Center(
                              child: AudioPlaceholder(size: 36),
                            ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title + artist — tap navigates to detail
            Expanded(
              child: GestureDetector(
                onTap: onDetails,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                isCurrentlyPlaying ? colorScheme.primary : null,
                            fontWeight:
                                isCurrentlyPlaying ? FontWeight.bold : null,
                          ),
                    ),
                    if (media.artists.isNotEmpty)
                      Text(
                        media.artists.map((a) => a.name).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ),
            // Actions
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.red : null,
                size: 20,
              ),
              onPressed: onFavorite,
              tooltip: isFavorite ? l.removeFromFavorites : l.addToFavorites,
            ),
            if (onDownload != null)
              IconButton(
                icon: isDownloading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: downloadProgress > 0 ? downloadProgress : null,
                        ),
                      )
                    : Icon(
                        isDownloaded
                            ? Icons.check_circle
                            : Icons.cloud_download,
                        color: isDownloaded ? colorScheme.primary : null,
                        size: 20,
                      ),
                onPressed: onDownload,
                tooltip: isDownloaded
                    ? l.downloaded
                    : isDownloading
                        ? l.downloading
                        : l.download,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) {
                switch (value) {
                  case 'play':
                    onPlay?.call();
                  case 'add_to_queue':
                    onAddToQueue?.call();
                  case 'add_to_collection':
                    onAddToCollection?.call();
                  case 'edit_metadata':
                    onEditMetadata?.call();
                  case 'details':
                    onDetails?.call();
                }
              },
              // Мёртвые пункты меню: показываем только те, для которых
              // есть обработчики.
              itemBuilder: (context) => [
                if (onPlay != null)
                  PopupMenuItem(value: 'play', child: Text(l.play)),
                if (onAddToQueue != null)
                  PopupMenuItem(
                    value: 'add_to_queue',
                    child: Text(l.addToQueue),
                  ),
                if (onAddToCollection != null)
                  PopupMenuItem(
                    value: 'add_to_collection',
                    child: Text(l.addToCollection),
                  ),
                if (onEditMetadata != null)
                  PopupMenuItem(
                    value: 'edit_metadata',
                    child: Text(l.editMetadata),
                  ),
                if (onDetails != null)
                  PopupMenuItem(value: 'details', child: Text(l.details)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

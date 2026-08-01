import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Flat track row for audio listings with cover, title, artist, and actions.
/// Tap on cover starts/pauses playback; long-press opens the detail page.
class AudioTrackRow extends ConsumerWidget {
  const AudioTrackRow({
    super.key,
    required this.media,
    this.isPlaying = false,
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
  final bool isPlaying;
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
    final thumbUrl = '$baseUrl/media/${media.id}/thumb';
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    final downloadState = ref.watch(downloadNotifierProvider(media.id));
    final isDownloaded = downloadState is DownloadDownloaded;
    final isDownloading = downloadState is DownloadDownloading;
    final downloadProgress = switch (downloadState) {
      DownloadDownloading(:final progress) => progress,
      _ => 0.0,
    };

    final playbackState = ref.watch(playbackCoordinatorProvider);
    final isCurrentlyPlaying = playbackState is PlaybackPlaying &&
        playbackState.media.id == media.id;

    return InkWell(
      onTap: onPlay,
      onLongPress: onDetails,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: isCurrentlyPlaying
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // Cover — tap toggles play/pause
            GestureDetector(
              onTap: () {
                final current = ref.read(playbackCoordinatorProvider);
                if (current is PlaybackPlaying && current.media.id == media.id) {
                  if (current.isPaused) {
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
                      ? Container(
                          color: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.equalizer,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                        )
                      : AuthNetworkImage(
                          imageUrl: thumbUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: colorScheme.primaryContainer,
                            child: Icon(Icons.music_note,
                                color: colorScheme.primary, size: 24),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.primaryContainer,
                            child: Icon(Icons.music_note,
                                color: colorScheme.primary, size: 24),
                          ),
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
                            color: isCurrentlyPlaying
                                ? colorScheme.primary
                                : null,
                            fontWeight: isCurrentlyPlaying
                                ? FontWeight.bold
                                : null,
                          ),
                    ),
                    if (media.artist != null && media.artist!.isNotEmpty)
                      Text(
                        media.artist!,
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
              tooltip: isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
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
                        isDownloaded ? Icons.check_circle : Icons.cloud_download,
                        color: isDownloaded ? colorScheme.primary : null,
                        size: 20,
                      ),
                onPressed: isDownloading ? null : onDownload,
                tooltip: isDownloaded
                    ? 'Downloaded'
                    : isDownloading
                        ? 'Downloading...'
                        : 'Download',
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
              itemBuilder: (context) => [
                PopupMenuItem(value: 'play', child: Text(l.play)),
                PopupMenuItem(
                    value: 'add_to_queue', child: Text(l.addToQueue)),
                PopupMenuItem(
                    value: 'add_to_collection',
                    child: Text(l.addToCollection)),
                PopupMenuItem(
                    value: 'edit_metadata', child: Text(l.editMetadata)),
                PopupMenuItem(value: 'details', child: Text(l.details)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_image_url.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Metadata + action buttons for a video. Stateless presentation: parent
/// (VideoDetailScreen) owns any stateful side effects (e.g. cover-upload
/// spinner) and passes them through callbacks.
class VideoDetailsPanel extends ConsumerWidget {
  const new({
    required this.media,
    this.onChangeCover,
    this.onEditMetadata,
    this.onDelete,
    this.onToggleFavorite,
    this.onAddToCollection,
    this.onDownload,
    this.onAddToQueue,
    this.onPlay,
    super.key,
  });

  final Media media;
  final Future<void> Function()? onChangeCover;
  final Future<void> Function()? onEditMetadata;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onToggleFavorite;
  final Future<void> Function()? onAddToCollection;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onAddToQueue;
  final Future<void> Function()? onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final favoriteState = ref.watch(favoriteToggleProvider(media.id));
    final isFavorite = favoriteState.value;
    final downloadState = ref.watch(downloadNotifierProvider(media.id));

    final downloadProgress = switch (downloadState) {
      DownloadDownloading(:final progress) => progress,
      _ => 0.0,
    };
    final isDownloading = downloadState is DownloadDownloading;
    final hasCover = media.coverUrl != null && media.coverUrl!.isNotEmpty;
    final baseUrl = ref.watch(baseUrlProvider);
    final coverUrl = buildMediaImageUrl(
      baseUrl: baseUrl,
      mediaId: media.id,
      kind: hasCover ? MediaImageKind.cover : MediaImageKind.thumb,
      cacheBust: media.updatedAt?.millisecondsSinceEpoch,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCover) ...[
            AuthNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              height: 200,
              width: double.infinity,
              placeholder: (_, _) => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, _, _) => const SizedBox(
                height: 200,
                child: Center(child: Icon(Icons.broken_image, size: 64)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            media.title,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            () {
              final parts = <String>[
                if (hasMediaYear(media.year)) '${media.year}',
                media.type.value,
              ];
              return parts.join(' · ');
            }(),
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.white70),
          ),
          if (media.artists.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              media.artists.map((a) => a.name).join(', '),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
          ],
          if (media.album != null && media.album!.isNotEmpty) ...[
            Text(
              media.album!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
          ],
          if (media.genre != null && media.genre!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Chip(
              label: Text(
                media.genre!,
                style: const TextStyle(color: Colors.white),
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white24,
            ),
          ],
          if (media.description != null) ...[
            const SizedBox(height: 16),
            Text(
              media.description!,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (media.duration != null && media.duration! > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${l.duration}: '
              '${Duration(seconds: media.duration!).formatted}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: l.play,
              child: FilledButton.icon(
                onPressed: onPlay == null ? null : () => onPlay!.call(),
                icon: const Icon(Icons.play_arrow),
                label: Text(l.play),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: l.favorites,
                  child: OutlinedButton.icon(
                    onPressed: isFavorite == null
                        ? null
                        : onToggleFavorite == null
                        ? null
                        : () => onToggleFavorite?.call(),
                    icon: Icon(
                      (isFavorite ?? false)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: isFavorite == null
                          ? null
                          : (isFavorite ? Colors.red : null),
                    ),
                    label: Text(l.favorites),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: l.myCollections,
                  child: OutlinedButton.icon(
                    onPressed: () => onAddToCollection?.call(),
                    icon: const Icon(Icons.add_to_queue),
                    label: Text(l.myCollections),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: isDownloading ? l.cancel : l.download,
                  child: OutlinedButton.icon(
                    onPressed: () => onDownload?.call(),
                    icon: isDownloading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: downloadProgress > 0
                                  ? downloadProgress
                                  : null,
                            ),
                          )
                        : Icon(
                            downloadState is DownloadDownloaded
                                ? Icons.check_circle
                                : Icons.cloud_download,
                            color: downloadState is DownloadDownloaded
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                    label: Text(switch (downloadState) {
                      DownloadDownloading(:final progress) =>
                        progress > 0
                            ? '${(progress * 100).toInt()}%'
                            : l.downloading,
                      DownloadDownloaded() => l.downloaded,
                      DownloadError() => l.errorLabel,
                      _ => l.download,
                    }),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: l.addToQueue,
              child: OutlinedButton.icon(
                onPressed: () => onAddToQueue?.call(),
                icon: const Icon(Icons.queue_music_outlined),
                label: Text(l.addToQueue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

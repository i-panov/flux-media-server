import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/widgets/audio_placeholder.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_image_url.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

class MediaCard extends ConsumerWidget {
  const MediaCard({
    required this.media,
    super.key,
    this.onTap,
    this.isFavorite = false,
    this.onFavorite,
    this.isDownloaded = false,
    this.onDownload,
  });

  final Media media;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final bool isDownloaded;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final baseUrl = ref.watch(baseUrlProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final hasCover = media.coverUrl != null && media.coverUrl!.isNotEmpty;
    // Cache-buster: CachedNetworkImage caches by URL, so append updatedAt
    // to force a reload when the cover changes on the server.
    final imageUrl = buildMediaImageUrl(
      baseUrl: baseUrl,
      mediaId: media.id,
      kind: hasCover ? MediaImageKind.cover : MediaImageKind.thumb,
      cacheBust: media.updatedAt?.millisecondsSinceEpoch,
    );

    Widget imageWidget = AuthNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => const Center(
        child: SkeletonWidget(width: double.infinity, height: double.infinity),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, size: 48),
      ),
    );

    // For files without cover, show programmatic placeholder for audio.
    if (!hasCover && media.type == MediaType.audio) {
      imageWidget = const Center(
        child: AudioPlaceholder(size: 120),
      );
    }

    return RepaintBoundary(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: imageWidget,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (media.artists.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            media.artists.map((a) => a.name).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                    ),
                          ),
                        ],
                        // 0 = «нет данных» на бэкенде — не показываем.
                        if (hasMediaYear(media.year)) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${media.year}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // Favorite overlay
              Positioned(
                top: 4,
                right: 4,
                child: Semantics(
                  button: true,
                  label: l.favorites,
                  child: Tooltip(
                    message: l.favorites,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: onFavorite,
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(
                            isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 16,
                            color: isFavorite ? Colors.red : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Download overlay
              if (onDownload != null)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Semantics(
                    button: true,
                    label: isDownloaded ? l.downloaded : l.download,
                    child: Tooltip(
                      message: isDownloaded ? l.downloaded : l.download,
                      child: Material(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: onDownload,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(
                              isDownloaded
                                  ? Icons.check_circle
                                  : Icons.cloud_download_outlined,
                              size: 16,
                              color: isDownloaded
                                  ? colorScheme.primary
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

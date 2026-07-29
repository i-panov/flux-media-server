import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// A track row for audio listings with cover, title, artist, and actions.
class AudioTrackRow extends ConsumerWidget {
  const AudioTrackRow({
    super.key,
    required this.media,
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
    final baseUrl = ref.watch(baseUrlProvider);
    final thumbUrl = '$baseUrl/media/${media.id}/thumb';
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: colorScheme.primaryContainer,
          child: ClipOval(
            child: AuthNetworkImage(
              imageUrl: thumbUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Icon(Icons.music_note, color: colorScheme.primary),
              errorWidget: (_, __, ___) =>
                  Icon(Icons.music_note, color: colorScheme.primary),
            ),
          ),
        ),
        title: Text(media.title),
        subtitle: Text(media.artist ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.red : null,
                size: 20,
              ),
              onPressed: onFavorite,
              tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            ),
            if (onDownload != null)
              IconButton(
                icon: Icon(
                  isDownloaded ? Icons.check_circle : Icons.cloud_download,
                  color: isDownloaded ? colorScheme.primary : null,
                  size: 20,
                ),
                onPressed: onDownload,
                tooltip: isDownloaded ? 'Downloaded' : 'Download',
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

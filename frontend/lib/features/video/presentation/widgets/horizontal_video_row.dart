import 'package:flutter/material.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// A horizontal scrollable row of media cards with a section title.
class HorizontalVideoRow extends StatelessWidget {
  const HorizontalVideoRow({
    required this.title,
    required this.icon,
    required this.items,
    required this.onItemTapped,
    super.key,
    this.isFavoriteMap = const {},
    this.onFavoriteToggled,
    this.isDownloadedMap = const {},
    this.onDownloadToggled,
  });

  final String title;
  final IconData icon;
  final List<Media> items;
  final ValueChanged<int> onItemTapped;
  final Map<int, bool> isFavoriteMap;
  final ValueChanged<int>? onFavoriteToggled;
  final Map<int, bool> isDownloadedMap;
  final ValueChanged<int>? onDownloadToggled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final media = items[index];
              return SizedBox(
                width: 160,
                child: MediaCard(
                  media: media,
                  onTap: () => onItemTapped(media.id),
                  isFavorite: isFavoriteMap[media.id] ?? false,
                  onFavorite: onFavoriteToggled != null
                      ? () => onFavoriteToggled!(media.id)
                      : null,
                  isDownloaded: isDownloadedMap[media.id] ?? false,
                  onDownload: onDownloadToggled != null
                      ? () => onDownloadToggled!(media.id)
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

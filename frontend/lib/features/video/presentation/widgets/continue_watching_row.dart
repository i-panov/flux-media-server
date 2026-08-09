import 'package:flutter/material.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// A row of media cards with progress bar overlay for "Continue Watching".
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    required this.items,
    required this.onItemTapped,
    super.key,
    this.isFavoriteMap = const {},
    this.onFavoriteToggled,
    this.isDownloadedMap = const {},
    this.onDownloadToggled,
  });

  final List<(Media, WatchProgress)> items;
  final ValueChanged<int> onItemTapped;
  final Map<int, bool> isFavoriteMap;
  final ValueChanged<int>? onFavoriteToggled;
  final Map<int, bool> isDownloadedMap;
  final ValueChanged<int>? onDownloadToggled;

  double _progress((Media, WatchProgress) item) {
    final duration = item.$1.duration ?? 0;
    if (duration == 0) return 0;
    return item.$2.position / duration;
  }

  bool _isCompleted((Media, WatchProgress) item) {
    final duration = item.$1.duration ?? 0;
    return duration > 0 && item.$2.position >= duration * 0.9;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final h = hours.toString().padLeft(2, '0');
    final m = minutes.toString().padLeft(2, '0');
    final s = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l.continueWatching,
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
              final item = items[index];
              final progress = _progress(item);
              final completed = _isCompleted(item);
              final remaining = Duration(
                seconds: (item.$1.duration ?? 0) - item.$2.position,
              );

              return SizedBox(
                width: 160,
                child: Stack(
                  children: [
                    MediaCard(
                      media: item.$1,
                      onTap: () => onItemTapped(item.$1.id),
                      isFavorite: isFavoriteMap[item.$1.id] ?? false,
                      onFavorite: onFavoriteToggled != null
                          ? () => onFavoriteToggled!(item.$1.id)
                          : null,
                      isDownloaded: isDownloadedMap[item.$1.id] ?? false,
                      onDownload: onDownloadToggled != null
                          ? () => onDownloadToggled!(item.$1.id)
                          : null,
                    ),
                    // Progress bar at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: completed ? 1.0 : progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.black26,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          completed
                              ? Theme.of(context).colorScheme.primary
                              : Colors.amber,
                        ),
                      ),
                    ),
                    // Remaining time overlay
                    if (!completed && progress > 0.05)
                      Positioned(
                        bottom: 4,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-${_formatDuration(remaining)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // "Completed" badge
                    if (completed)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l.done,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

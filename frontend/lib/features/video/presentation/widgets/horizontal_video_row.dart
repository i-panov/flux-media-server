import 'package:flutter/material.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/features/video/presentation/utils/watch_progress.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// Горизонтальный ряд карточек медиа с заголовком секции.
///
/// Один виджет и для «Продолжить просмотр» (прогресс передаётся через
/// [progressById]), и для обычных секций — раньше было два почти
/// одинаковых виджета.
class HorizontalVideoRow extends StatelessWidget {
  const HorizontalVideoRow({
    required this.title,
    required this.icon,
    required this.items,
    required this.onItemTapped,
    super.key,
    this.progressById = const {},
    this.isFavoriteMap = const {},
    this.onFavoriteToggled,
    this.isDownloadedMap = const {},
    this.onDownloadToggled,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Media> items;
  final ValueChanged<int> onItemTapped;
  final Map<int, WatchProgress> progressById;
  final Map<int, bool> isFavoriteMap;
  final ValueChanged<int>? onFavoriteToggled;
  final Map<int, bool> isDownloadedMap;
  final ValueChanged<int>? onDownloadToggled;
  final Widget? trailing;

  int _durationSeconds(Media media) {
    final progress = progressById[media.id];
    return progress != null && progress.duration > 0
        ? progress.duration
        : (media.duration ?? 0);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(icon: icon, title: title, trailing: trailing),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final media = items[index];
              final progress = progressById[media.id];
              return SizedBox(
                width: 160,
                child: progress == null
                    ? _buildCard(context, media)
                    : _buildProgressCard(context, media, progress),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, Media media) {
    return MediaCard(
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
    );
  }

  Widget _buildProgressCard(
    BuildContext context,
    Media media,
    WatchProgress progress,
  ) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final duration = _durationSeconds(media);
    final completed = isWatchCompleted(
      position: progress.position,
      duration: duration,
      completed: progress.completed,
    );
    final fraction =
        duration > 0 ? (progress.position / duration).clamp(0.0, 1.0) : 0.0;
    final secondsLeft = (duration - progress.position).clamp(0, 359999);

    return Stack(
      children: [
        _buildCard(context, media),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            value: completed ? 1.0 : fraction,
            minHeight: 4,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              completed ? colorScheme.primary : colorScheme.tertiary,
            ),
          ),
        ),
        if (!completed && fraction > 0.05)
          Positioned(
            bottom: 4,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '-${_formatDuration(Duration(seconds: secondsLeft))}',
                style: TextStyle(
                  color: colorScheme.onInverseSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (completed)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l.done,
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

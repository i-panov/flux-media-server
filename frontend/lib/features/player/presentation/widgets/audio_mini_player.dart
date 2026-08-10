import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/audio_placeholder.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Mini-player bar shown above the bottom navigation bar during audio playback.
class AudioMiniPlayer extends ConsumerStatefulWidget {
  const AudioMiniPlayer({super.key, this.disableTap = false});

  /// When true, tapping the mini-player does not navigate to the full
  /// player screen (used when already displayed inside the player screen).
  final bool disableTap;

  @override
  ConsumerState<AudioMiniPlayer> createState() => _AudioMiniPlayerState();
}

String _formatDuration(Duration? d) {
  if (d == null) return '0:00';
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _AudioMiniPlayerState extends ConsumerState<AudioMiniPlayer> {
  double _volume = 100;
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    // Volume slider is desktop-only; no need to track volume on mobile.
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final audioDs = ref.read(audioPlayerDatasourceProvider);
      _volumeSub = audioDs.volumeStream.listen((v) {
        if (mounted) setState(() => _volume = v);
      });
    }
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Watch the full state but only rebuild when the selected fields change.
    // Position updates every second cause the progress bar and time labels
    // to update, which is intentional for the mini-player UI.
    final playbackInfo = ref.watch(
      playbackCoordinatorProvider.select((state) {
        return switch (state) {
          PlaybackPlaying(
            :final media,
            :final type,
            :final isPaused,
            :final position,
            :final duration,
          ) =>
            (media, type, isPaused, position, duration),
          _ => null,
        };
      }),
    );
    final baseUrl = ref.watch(baseUrlProvider);

    final info = playbackInfo;
    if (info == null) return const SizedBox.shrink();
    final (
      Media media,
      String type,
      bool isPaused,
      Duration position,
      Duration? duration
    ) = info;
    if (type != 'audio') return const SizedBox.shrink();

    final progress = (duration != null && duration > Duration.zero)
        ? position.inMicroseconds / duration.inMicroseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seek bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text(
                _formatDuration(position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      if (duration != null && duration > Duration.zero) {
                        final newPos = Duration(
                          microseconds:
                              (value * duration.inMicroseconds).toInt(),
                        );
                        ref
                            .read(playbackCoordinatorProvider.notifier)
                            .seek(newPos);
                      }
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: InkWell(
            onTap: widget.disableTap
                ? null
                : () => context.router.push(AudioPlayerRoute(media: media)),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  // Cover — tap toggles play/pause
                  GestureDetector(
                    onTap: () {
                      if (isPaused) {
                        ref.read(playbackCoordinatorProvider.notifier).resume();
                      } else {
                        ref.read(playbackCoordinatorProvider.notifier).pause();
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: () {
                          final hasCover = media.coverUrl != null &&
                              media.coverUrl!.isNotEmpty;
                          if (!hasCover) {
                            return const Center(
                              child: AudioPlaceholder(size: 28),
                            );
                          }
                          final cacheBuster =
                              media.updatedAt?.millisecondsSinceEpoch;
                          final buster =
                              cacheBuster != null ? '?v=$cacheBuster' : '';
                          return AuthNetworkImage(
                            imageUrl: '$baseUrl/media/${media.id}/cover$buster',
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.music_note,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                            ),
                          );
                        }(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          media.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          media.artists.map((a) => a.name).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  // Previous track
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    tooltip: l.previous,
                    onPressed: () {
                      ref.read(playQueueProvider.notifier).previous();
                    },
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  // Play/pause
                  IconButton(
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    tooltip: isPaused ? l.play : l.pause,
                    onPressed: () {
                      if (isPaused) {
                        ref.read(playbackCoordinatorProvider.notifier).resume();
                      } else {
                        ref.read(playbackCoordinatorProvider.notifier).pause();
                      }
                    },
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  // Next track
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: l.next,
                    onPressed: () async {
                      final success = await ref
                          .read(playQueueProvider.notifier)
                          .next();
                      // If there's no next track, stop playback.
                      if (!success && context.mounted) {
                        ref
                            .read(playbackCoordinatorProvider.notifier)
                            .stop();
                      }
                    },
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  // Volume slider — desktop only (mobile uses physical
                  // buttons).
                  if (Platform.isLinux ||
                      Platform.isWindows ||
                      Platform.isMacOS) ...[
                    SizedBox(
                      width: 140,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _volume == 0
                                ? Icons.volume_off
                                : _volume < 50
                                    ? Icons.volume_down
                                    : Icons.volume_up,
                            size: 18,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor:
                                    Theme.of(context).colorScheme.primary,
                                inactiveTrackColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                thumbColor:
                                    Theme.of(context).colorScheme.primary,
                                overlayColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.1),
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                              ),
                              child: Slider(
                                value: _volume,
                                max: 100,
                                onChanged: (value) {
                                  ref
                                      .read(
                                        playbackCoordinatorProvider.notifier,
                                      )
                                      .setVolume(value);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Favorite
                  IconButton(
                    icon: Icon(
                      ref.watch(favoriteToggleProvider(media.id)).valueOrNull ??
                              false
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                    tooltip: l.favorites,
                    onPressed: () {
                    ref
                        .read(favoriteToggleProvider(media.id).notifier)
                        .toggle();
                    },
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: l.close,
                    onPressed: () {
                      ref.read(playbackCoordinatorProvider.notifier).stop();
                      if (widget.disableTap) {
                        Navigator.of(context).maybePop();
                      }
                    },
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

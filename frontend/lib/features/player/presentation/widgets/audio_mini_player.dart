import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Mini-player bar shown above the bottom navigation bar during audio playback.
class AudioMiniPlayer extends ConsumerStatefulWidget {
  const AudioMiniPlayer({super.key});

  @override
  ConsumerState<AudioMiniPlayer> createState() => _AudioMiniPlayerState();
}

class _AudioMiniPlayerState extends ConsumerState<AudioMiniPlayer> {
  double _volume = 100.0;
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    final audioDs = ref.read(audioPlayerDatasourceProvider);
    _volumeSub = audioDs.volumeStream.listen((v) {
      if (mounted) setState(() => _volume = v);
    });
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Select only the fields this widget needs so position/duration ticks
    // don't rebuild the mini-player every second.
    final playbackInfo =
        ref.watch(playbackCoordinatorProvider.select((state) {
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
    }));
    final baseUrl = ref.watch(baseUrlProvider);

    final info = playbackInfo;
    if (info == null) return const SizedBox.shrink();
    final (Media media, String type, bool isPaused, Duration position,
          Duration? duration) = info;
    if (type != 'audio') return const SizedBox.shrink();

    final progress = (duration != null && duration > Duration.zero)
        ? position.inMicroseconds / duration.inMicroseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 2,
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: InkWell(
            onTap: () => context.router.push(AudioPlayerRoute(media: media)),
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
                      child: AuthNetworkImage(
                        imageUrl: '$baseUrl/media/${media.id}/thumb',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.music_note,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20),
                        ),
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
                          media.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    tooltip: isPaused ? 'Play' : 'Pause',
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
                  // Volume slider
                  SizedBox(
                    width: 80,
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Theme.of(context).colorScheme.primary,
                              inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              thumbColor: Theme.of(context).colorScheme.primary,
                              overlayColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            ),
                            child: Slider(
                              value: _volume,
                              min: 0,
                              max: 100,
                              onChanged: (value) {
                                ref.read(playbackCoordinatorProvider.notifier).setVolume(value);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    onPressed: () {
                      ref.read(playbackCoordinatorProvider.notifier).stop();
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

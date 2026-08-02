import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/lyrics/presentation/providers/lyrics_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key, required this.media});
  final Media media;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Auto-play this media if not already playing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playback = ref.read(playbackCoordinatorProvider);
      final alreadyPlaying = playback is PlaybackPlaying &&
          playback.media.id == widget.media.id;
      if (!alreadyPlaying) {
        ref.read(playbackCoordinatorProvider.notifier).play(widget.media);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final playbackState = ref.watch(playbackCoordinatorProvider);
    final currentMedia = switch (playbackState) {
      PlaybackPlaying(:final media) => media,
      _ => widget.media,
    };

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.lyrics),
            Tab(text: l.translation),
            Tab(text: l.queue),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LyricsTab(media: currentMedia),
          _TranslationTab(media: currentMedia),
          const _QueueTab(),
        ],
      ),
      bottomNavigationBar: _PlayerControls(media: currentMedia),
    );
  }
}

class _LyricsTab extends ConsumerWidget {
  const _LyricsTab({required this.media});
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final lyricsState = ref.watch(lyricsProvider(media.id));
    final playbackState = ref.watch(playbackCoordinatorProvider);

    return lyricsState.maybeWhen(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorLoadingLyrics)),
      data: (lyrics) {
        if (lyrics == null || lyrics.lyricsText.isEmpty) {
          return Center(child: Text(l.noLyricsAvailable));
        }

        final syncLines = _parseLyricsSync(lyrics.syncData);

        if (syncLines.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Text(
              lyrics.lyricsText,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          );
        }

        Duration position = Duration.zero;
        if (playbackState is PlaybackPlaying) {
          position = playbackState.position;
        }

        int currentLineIndex = 0;
        for (int i = syncLines.length - 1; i >= 0; i--) {
          if (position >= syncLines[i].time) {
            currentLineIndex = i;
            break;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: syncLines.asMap().entries.map((entry) {
              final index = entry.key;
              final line = entry.value;
              final isCurrentLine = index == currentLineIndex;
              final isPastLine = index < currentLineIndex;
              final defaultStyle = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();

              TextStyle style;
              if (isCurrentLine) {
                style = Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ) ?? defaultStyle;
              } else if (isPastLine) {
                style = defaultStyle.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    );
              } else {
                style = defaultStyle;
              }

              return AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: style,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(line.text),
                ),
              );
            }).toList(),
          ),
        );
      },
      orElse: () => Center(child: Text(l.noLyricsAvailable)),
    );
  }

  List<({Duration time, String text})> _parseLyricsSync(String syncData) {
    if (syncData.isEmpty) return [];
    final lines = syncData.split('\n');
    final result = <({Duration time, String text})>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final match = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)').firstMatch(trimmed);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final text = match.group(3) ?? '';
        result.add((time: Duration(minutes: minutes, seconds: seconds.toInt()), text: text.trim()));
      }
    }
    return result;
  }
}

class _TranslationTab extends ConsumerWidget {
  const _TranslationTab({required this.media});
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final lyricsState = ref.watch(lyricsProvider(media.id));

    return lyricsState.maybeWhen(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorLoadingTranslation)),
      data: (lyrics) {
        if (lyrics == null || lyrics.translation.isEmpty) {
          return Center(child: Text(l.noTranslationAvailable));
        }
        final lines = lyrics.translation.split('\n');
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: lines
                .where((l) => l.trim().isNotEmpty)
                .map((line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        line,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ))
                .toList(),
          ),
        );
      },
      orElse: () => Center(child: Text(l.noTranslationAvailable)),
    );
  }
}

class _QueueTab extends ConsumerWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final queueState = ref.watch(playQueueProvider);

    if (queueState.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.queue_music_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l.queueIsEmpty),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: queueState.items.length,
      itemBuilder: (context, index) {
        final item = queueState.items[index];
        final isCurrent = index == queueState.currentIndex;

        return ListTile(
          leading: Icon(
            isCurrent ? Icons.play_arrow : Icons.music_note,
            color: isCurrent ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(
            item.title,
            style: isCurrent
                ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)
                : null,
          ),
          subtitle: item.artist != null && item.artist!.isNotEmpty ? Text(item.artist!) : null,
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => ref.read(playQueueProvider.notifier).removeAt(index),
          ),
          onTap: () {
            ref.read(playQueueProvider.notifier).setQueue(
                  queueState.items,
                  startIndex: index,
                );
          },
        );
      },
    );
  }
}

class _PlayerControls extends ConsumerStatefulWidget {
  const _PlayerControls({required this.media});
  final Media media;

  @override
  ConsumerState<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<_PlayerControls> {
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
    final playbackState = ref.watch(playbackCoordinatorProvider);
    final queueState = ref.watch(playQueueProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return playbackState.maybeWhen(
      playing: (m, type, isPaused, position, duration, speed, savedPosition) {
        if (type != 'audio') return const SizedBox.shrink();
        final sliderValue = position.inSeconds.toDouble().clamp(
          0.0,
          (duration ?? position).inSeconds.toDouble().clamp(1.0, double.infinity),
        );
        final sliderMax = (duration ?? position).inSeconds.toDouble().clamp(1.0, double.infinity);

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek bar with time labels
              Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: colorScheme.primary,
                        inactiveTrackColor: colorScheme.surfaceContainerHighest,
                        thumbColor: colorScheme.primary,
                        overlayColor: colorScheme.primary.withOpacity(0.1),
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: sliderValue,
                        max: sliderMax,
                        onChanged: (value) {
                          ref.read(playbackCoordinatorProvider.notifier).seek(Duration(seconds: value.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(duration ?? Duration.zero),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              // Transport controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: queueState.hasPrevious
                        ? () => ref.read(playQueueProvider.notifier).previous()
                        : null,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    iconSize: 48,
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    onPressed: () {
                      if (isPaused) {
                        ref.read(playbackCoordinatorProvider.notifier).resume();
                      } else {
                        ref.read(playbackCoordinatorProvider.notifier).pause();
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: queueState.hasNext
                        ? () => ref.read(playQueueProvider.notifier).next()
                        : null,
                  ),
                ],
              ),
              // Volume control
              Row(
                children: [
                  Icon(
                    _volume == 0
                        ? Icons.volume_off
                        : _volume < 50
                            ? Icons.volume_down
                            : Icons.volume_up,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(
                    width: 120,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: colorScheme.primary,
                        inactiveTrackColor: colorScheme.surfaceContainerHighest,
                        thumbColor: colorScheme.primary,
                        overlayColor: colorScheme.primary.withOpacity(0.1),
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
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

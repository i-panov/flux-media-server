import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/presentation/widgets/audio_mini_player.dart';
import 'package:flux_media_server/features/lyrics/presentation/providers/lyrics_provider.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/upsert_lyrics.dart';
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
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
      bottomNavigationBar: const AudioMiniPlayer(disableTap: true),
    );
  }
}

class _LyricsTab extends ConsumerStatefulWidget {
  const _LyricsTab({required this.media});
  final Media media;

  @override
  ConsumerState<_LyricsTab> createState() => _LyricsTabState();
}

class _LyricsTabState extends ConsumerState<_LyricsTab> {
  bool _isEditing = false;
  final _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing(String currentText) {
    _controller.text = currentText;
    setState(() => _isEditing = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final upsert = ref.read(upsertLyricsProvider);
    final result = await upsert(
      UpsertLyricsParams(
        mediaId: widget.media.id,
        lyricsText: _controller.text,
        source: 'user',
      ),
    );
    setState(() => _isSaving = false);
    result.fold(
      (failure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l.errorLabel}: ${failure.message}')),
          );
        }
      },
      (_) {
        if (mounted) {
          ref.invalidate(lyricsProvider(widget.media.id));
          setState(() => _isEditing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.lyricsSaved)),
          );
        }
      },
    );
  }

  late final l = AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider(widget.media.id));
    final playbackState = ref.watch(playbackCoordinatorProvider);

    if (_isEditing) {
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: l.addLyricsHere,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isEditing = false),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: Text(_isSaving ? l.saving : l.save),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return lyricsState.maybeWhen(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorLoadingLyrics)),
      data: (lyrics) {
        final text = lyrics?.lyricsText ?? '';
        final syncData = lyrics?.syncData ?? '';

        if (text.isEmpty && syncData.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.noLyricsAvailable),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => _startEditing(''),
                  child: Text(l.editLyrics),
                ),
              ],
            ),
          );
        }

        final syncLines = _parseLyricsSync(syncData);

        return Stack(
          children: [
            if (syncLines.isEmpty)
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              )
            else
              _SyncedLyricsView(
                syncLines: syncLines,
                playbackState: playbackState is PlaybackPlaying
                    ? playbackState as PlaybackPlaying
                    : null,
              ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l.editLyrics,
                onPressed: () => _startEditing(text),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
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

class _SyncedLyricsView extends StatelessWidget {
  const _SyncedLyricsView({
    required this.syncLines,
    required this.playbackState,
  });
  final List<({Duration time, String text})> syncLines;
  final PlaybackPlaying? playbackState;

  @override
  Widget build(BuildContext context) {
    Duration position = playbackState?.position ?? Duration.zero;

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
  }
}

class _TranslationTab extends ConsumerStatefulWidget {
  const _TranslationTab({required this.media});
  final Media media;

  @override
  ConsumerState<_TranslationTab> createState() => _TranslationTabState();
}

class _TranslationTabState extends ConsumerState<_TranslationTab> {
  bool _isEditing = false;
  final _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing(String currentText) {
    _controller.text = currentText;
    setState(() => _isEditing = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final lyricsState = ref.read(lyricsProvider(widget.media.id));
    final existing = lyricsState.valueOrNull;
    final upsert = ref.read(upsertLyricsProvider);
    final result = await upsert(
      UpsertLyricsParams(
        mediaId: widget.media.id,
        lyricsText: existing?.lyricsText ?? '',
        translation: _controller.text,
        syncData: existing?.syncData ?? '',
        source: existing?.source ?? 'user',
      ),
    );
    setState(() => _isSaving = false);
    result.fold(
      (failure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l.errorLabel}: ${failure.message}')),
          );
        }
      },
      (_) {
        if (mounted) {
          ref.invalidate(lyricsProvider(widget.media.id));
          setState(() => _isEditing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.translationSaved)),
          );
        }
      },
    );
  }

  late final l = AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider(widget.media.id));

    if (_isEditing) {
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: l.addTranslationHere,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isEditing = false),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: Text(_isSaving ? l.saving : l.save),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return lyricsState.maybeWhen(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorLoadingTranslation)),
      data: (lyrics) {
        final text = lyrics?.translation ?? '';

        if (text.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.noTranslationAvailable),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => _startEditing(''),
                  child: Text(l.editTranslation),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l.editTranslation,
                onPressed: () => _startEditing(text),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
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
          subtitle: item.artists.isNotEmpty ? Text(item.artists.map((a) => a.name).join(', ')) : null,
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

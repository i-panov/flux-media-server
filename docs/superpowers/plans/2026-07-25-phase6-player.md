# Phase 6: Unified Player + Lyrics UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or executing-plans.

**Goal:** Реализовать unified player с mutual exclusion (audio/video), audio mini-player, full-screen audio player с Lyrics/Translation/Queue табами, video PiP. Интегрировать lyrics UI в audio player.

---

## Task 1: Create Playback Coordinator

**Files:**
- Create: `frontend/lib/features/player/data/providers/playback_coordinator.dart`

- [ ] **Step 1: Создать PlaybackCoordinator**

```dart
@freezed
class PlaybackState with _$PlaybackState {
  const factory PlaybackState.initial() = PlaybackInitial;
  const factory PlaybackState.playing({
    required Media media,
    required String type, // 'audio' or 'video'
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
  }) = PlaybackPlaying;
  const factory PlaybackState.completed() = PlaybackCompleted;
}

class PlaybackCoordinator extends StateNotifier<PlaybackState> {
  final PlayerNotifier _player;
  
  const PlaybackCoordinator(this._player) : super(const PlaybackState.initial());
  
  void play(Media media) {
    // Stop current playback, save progress, start new
    if (state is PlaybackPlaying) {
      // Save progress to backend
    }
    
    if (media.type == 'audio') {
      // Set state for audio playback
      // Show mini-player
    } else {
      // Navigate to video player fullscreen
    }
    
    state = PlaybackState.playing(
      media: media,
      type: media.type,
      isPaused: false,
    );
  }
  
  void pause() { ... }
  void resume() { ... }
  void seek(Duration position) { ... }
  void stop() { ... }
}
```

---

## Task 2: Create Audio Mini-Player Widget

**Files:**
- Create: `frontend/lib/features/player/presentation/widgets/audio_mini_player.dart`

- [ ] **Step 1: Создать AudioMiniPlayer**

```dart
class AudioMiniPlayer extends ConsumerWidget {
  const AudioMiniPlayer({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackCoordinatorProvider);
    
    return playbackState.when(
      initial: () => const SizedBox.shrink(),
      playing: (media, type, isPaused, position, duration) {
        if (type != 'audio') return const SizedBox.shrink();
        
        return Container(
          padding: const EdgeInsets.all(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              // Cover thumbnail 36px
              CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(...),
              ),
              const SizedBox(width: 8),
              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(media.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(media.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              // Play/Pause
              IconButton(
                icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                onPressed: () => ...toggle,
              ),
            ],
          ),
        );
      },
      completed: () => const SizedBox.shrink(),
    );
  }
}
```

---

## Task 3: Create Full-Screen Audio Player with Tabs

**Files:**
- Create: `frontend/lib/features/player/presentation/screens/audio_player_screen.dart`
- Modify: `frontend/lib/core/router/app_router.dart`

- [ ] **Step 1: Создать AudioPlayerScreen**

```dart
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
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context), // Swipe down to minimize
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Lyrics'),
            Tab(text: 'Translation'),
            Tab(text: 'Queue'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LyricsTab(media: widget.media),
          _TranslationTab(media: widget.media),
          _QueueTab(media: widget.media),
        ],
      ),
      bottomNavigationBar: _PlayerControls(media: widget.media),
    );
  }
}
```

- [ ] **Step 2: Создать Lyrics Tab**

```dart
class _LyricsTab extends ConsumerWidget {
  const _LyricsTab({required this.media});
  final Media media;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsState = ref.watch(lyricsProvider(media.id));
    final playerState = ref.watch(playerProvider);
    
    return lyricsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (lyrics) {
        if (lyrics == null || lyrics.lyricsText.isEmpty) {
          return const Center(child: Text('No lyrics available'));
        }
        
        // Parse LRC sync data if available
        final syncLines = _parseLyricsSync(lyrics.syncData);
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: syncLines.isEmpty ? 1 : syncLines.length,
          itemBuilder: (context, index) {
            if (syncLines.isEmpty) {
              // Non-synced lyrics - show as paragraphs
              return Text(lyrics.lyricsText, style: Theme.of(context).textTheme.headlineSmall);
            }
            
            final line = syncLines[index];
            // Highlight current line based on player position
            final isCurrentLine = _isCurrentLine(line, playerState);
            
            return AnimatedDefaultTextStyle(
              duration: Duration(milliseconds: 300),
              style: isCurrentLine 
                  ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )
                  : Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: isCurrentLine ? null : Colors.grey,
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(line.text),
              ),
            );
          },
        );
      },
    );
  }
  
  List<({Duration time, String text})> _parseLyricsSync(String syncData) {
    // Parse LRC format: [mm:ss.xx]text
    final lines = syncData.split('\n');
    return lines.map((line) {
      final match = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)').firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final text = match.group(3) ?? '';
        return (
          time: Duration(minutes: minutes, seconds: seconds.toInt()),
          text: text.trim(),
        );
      }
      return (time: Duration.zero, text: line);
    }).toList();
  }
  
  bool _isCurrentLine(({Duration time, String text}) line, PlayerNotifierState state) {
    if (state is! PlayerNotifierPlaying) return false;
    final position = state.position;
    // Simple: current line is the one whose time is closest to position
    return position >= line.time && position < line.time + Duration(seconds: 5);
  }
}
```

- [ ] **Step 3: Создать Translation Tab**

```dart
class _TranslationTab extends ConsumerWidget {
  const _TranslationTab({required this.media});
  final Media media;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsState = ref.watch(lyricsProvider(media.id));
    
    return lyricsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      data: (lyrics) {
        if (lyrics == null || lyrics.translation.isEmpty) {
          return const Center(child: Text('No translation available'));
        }
        
        // Parse synced translation and show line-by-line
        final lines = lyrics.translation.split('\n');
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(lines[index], style: Theme.of(context).textTheme.bodyLarge),
            );
          },
        );
      },
      orElse: () => const Center(child: Text('No translation available')),
    );
  }
}
```

- [ ] **Step 4: Создать Queue Tab**

```dart
class _QueueTab extends ConsumerWidget {
  const _QueueTab({required this.media});
  final Media media;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Show upcoming tracks from the same artist/library
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('Queue coming soon', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
```

---

## Task 4: Update MainScreen with Mini-Player

**Files:**
- Modify: `frontend/lib/core/router/app_router.dart` (MainScreen)

- [ ] **Step 1: Добавить AudioMiniPlayer над NavigationBar**

В MainScreen добавить `bottomNavigationBar` с AudioMiniPlayer:

```dart
bottomNavigationBuilder: (context, tabsRouter) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AudioMiniPlayer(), // Above nav bar
      NavigationBar(...), // Existing navigation
    ],
  );
}
```

---

## Task 5: Update PlayerScreen for Video PiP

**Files:**
- Modify: `frontend/lib/features/player/presentation/screens/player_screen.dart`

- [ ] **Step 1: Добавить PiP button**

В контролах video player добавить кнопку PiP:

```dart
IconButton(
  icon: const Icon(Icons.picture_in_picture_alt),
  onPressed: () {
    // TODO: Implement PiP using flutter_pip or platform channel
    debugPrint('PiP requested');
  },
)
```

---

## Task 6: Update PlayerProvider to support Audio

**Files:**
- Modify: `frontend/lib/features/player/presentation/providers/player_provider.dart`

- [ ] **Step 1: Добавить audio datasource**

Добавить `AudioPlayerDatasource` provider для audio playback.

---

## Task 7: Build Verification

- [ ] **Step 1: Run build_runner**

- [ ] **Step 2: Run analyzer**

- [ ] **Step 3: Build linux**

- [ ] **Step 4: Run tests**

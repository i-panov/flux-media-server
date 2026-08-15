import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Minimal interface for playback control, used by [PlayQueueNotifier].
/// This abstraction allows testing the queue logic without instantiating
/// a full [PlaybackCoordinator] (which requires media_kit Player instances).
abstract class PlaybackController {
  Future<void> play(Media media);
  Future<void> stop();
}

/// Manages a play queue: ordered list of media items with current index.
/// Supports next/previous, add, remove, and reorder.
class PlayQueueNotifier extends Notifier<PlayQueueState> {
  late final PlaybackController _coordinator;

  @override
  PlayQueueState build() {
    _coordinator = ref.watch(playbackControllerProvider);
    return const PlayQueueState();
  }

  /// Sets the queue to [items], starting playback from [startIndex].
  /// [startIndex] зажимается в допустимый диапазон.
  Future<void> setQueue(List<Media> items, {int startIndex = 0}) async {
    if (items.isEmpty) {
      state = const PlayQueueState();
      return;
    }
    final index = startIndex.clamp(0, items.length - 1);
    state = PlayQueueState(items: items, currentIndex: index);
    // Ошибка воспроизведения уже отражена в PlaybackState.error —
    // не пробрасываем её в UI-вызовы (часто fire-and-forget).
    try {
      await _coordinator.play(items[index]);
    } catch (_) {}
  }

  /// Adds a single item to the end of the queue.
  void enqueue(Media item) {
    final items = [...state.items, item];
    state = PlayQueueState(
      items: items,
      // Первый трек в пустой очереди становится текущим.
      currentIndex: state.currentIndex < 0 ? 0 : state.currentIndex,
    );
  }

  /// Adds multiple items to the queue.
  void enqueueAll(List<Media> items) {
    final newItems = [...state.items, ...items];
    state = PlayQueueState(
      items: newItems,
      currentIndex: state.currentIndex < 0 ? 0 : state.currentIndex,
    );
  }

  /// Перезапускает текущий трек очереди (например, play из системного
  /// уведомления после завершения воспроизведения).
  Future<bool> playCurrent() async {
    if (state.currentIndex < 0 || state.currentIndex >= state.items.length) {
      return false;
    }
    try {
      await _coordinator.play(state.items[state.currentIndex]);
    } catch (_) {}
    return true;
  }

  /// Plays the next track in the queue.
  /// Returns false if there is no next track.
  Future<bool> next() async {
    if (state.currentIndex + 1 >= state.items.length) return false;
    final newIndex = state.currentIndex + 1;
    state = state.copyWith(currentIndex: newIndex);
    try {
      await _coordinator.play(state.items[newIndex]);
    } catch (_) {}
    return true;
  }

  /// Plays the previous track in the queue.
  /// Returns false if there is no previous track.
  Future<bool> previous() async {
    if (state.currentIndex <= 0) return false;
    final newIndex = state.currentIndex - 1;
    state = state.copyWith(currentIndex: newIndex);
    try {
      await _coordinator.play(state.items[newIndex]);
    } catch (_) {}
    return true;
  }

  /// Removes item at [index] from the queue.
  void removeAt(int index) {
    if (index < 0 || index >= state.items.length) return;
    final items = List<Media>.from(state.items)..removeAt(index);

    final wasPlaying = index == state.currentIndex;

    int newIndex;
    if (items.isEmpty) {
      newIndex = -1;
    } else if (index < state.currentIndex) {
      newIndex = state.currentIndex - 1;
    } else {
      // index == currentIndex: следующий трек занимает тот же индекс.
      // index > currentIndex: текущий индекс не меняется.
      newIndex = state.currentIndex.clamp(0, items.length - 1);
    }

    state = PlayQueueState(
      items: items,
      currentIndex: newIndex,
    );

    // If we removed the currently playing item, stop playback.
    // The queue is now empty — coordinator should stop playback.
    if (items.isEmpty) {
      unawaited(_coordinator.stop());
    }
    // If we removed the currently playing track and there are more items,
    // auto-advance to the new currentIndex (which is the next track).
    else if (wasPlaying && newIndex >= 0 && newIndex < items.length) {
      unawaited(
        _coordinator.play(items[newIndex]).catchError((_) {}),
      );
    }
  }

  /// Clears the queue and stops playback.
  void clear() {
    state = const PlayQueueState();
    unawaited(_coordinator.stop());
  }

  /// Returns the current media item, or null if queue is empty.
  Media? get current =>
      state.currentIndex >= 0 && state.currentIndex < state.items.length
          ? state.items[state.currentIndex]
          : null;

  /// Returns upcoming items after the current one.
  List<Media> get upcoming => state.currentIndex + 1 < state.items.length
      ? state.items.sublist(state.currentIndex + 1)
      : [];
}

/// State of the play queue.
class PlayQueueState {
  const PlayQueueState({
    this.items = const [],
    this.currentIndex = -1,
  });

  final List<Media> items;
  final int currentIndex;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  bool get hasNext => currentIndex + 1 < items.length;
  bool get hasPrevious => currentIndex > 0;

  PlayQueueState copyWith({
    List<Media>? items,
    int? currentIndex,
  }) {
    return PlayQueueState(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

/// DI-точка контроллера воспроизведения для очереди: в проде — реальный
/// координатор, в тестах — фейк (без media_kit).
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  return ref.read(playbackCoordinatorProvider.notifier);
});

/// Provider for the play queue.
final playQueueProvider = NotifierProvider<PlayQueueNotifier, PlayQueueState>(
  PlayQueueNotifier.new,
);

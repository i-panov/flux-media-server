import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Minimal interface for playback control, used by [PlayQueueNotifier].
/// This abstraction allows testing the queue logic without instantiating
/// a full [PlaybackCoordinator] (which requires media_kit Player instances).
abstract class PlaybackController {
  /// Загружает текущую очередь в mpv и стартует с [startIndex].
  Future<void> startQueue({required int startIndex});

  /// Дописывает [items] в конец уже загруженного плейлиста, не прерывая
  /// воспроизведение.
  Future<void> enqueue(List<Media> items);

  /// Переход к следующему треку. `false` — следующего нет.
  Future<bool> next();

  /// Переход к предыдущему треку. `false` — предыдущего нет.
  Future<bool> previous();

  /// Переход к треку по индексу очереди. `false` — индекс некорректен.
  Future<bool> jump(int index);

  /// Удаление элемента очереди; индексы очереди и mpv совпадают.
  Future<void> removeAt(int index);

  /// Перезапуск текущего трека (например, play из уведомления после
  /// завершения воспроизведения).
  Future<void> restartCurrent();

  /// Индекс текущего трека по данным mpv.
  Stream<int> get playlistIndexStream;

  Future<void> stop();
}

/// Manages a play queue: ordered list of media items with current index.
/// Supports next/previous, add, remove, and reorder.
///
/// Список треков — источник истины для UI, а текущий индекс приходит из
/// mpv: переход между треками инициирует mpv, поэтому считать его в
/// Dart («+1») значило бы расходиться с реальным воспроизведением.
class PlayQueueNotifier extends Notifier<PlayQueueState> {
  late final PlaybackController _coordinator;
  StreamSubscription<int>? _indexSub;

  @override
  PlayQueueState build() {
    _coordinator = ref.watch(playbackControllerProvider);
    _indexSub = _coordinator.playlistIndexStream.listen(_onMpvIndex);
    ref.onDispose(() => unawaited(_indexSub?.cancel()));
    return const PlayQueueState();
  }

  void _onMpvIndex(int index) {
    if (index < 0 || index == state.currentIndex) return;
    if (index >= state.items.length) return;
    state = state.copyWith(currentIndex: index);
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
    // не пробрасываем её в UI-вызовы (часто fire-and-forget), но пишем
    // в лог: раньше ошибка здесь терялась молча и выглядела как «плеер
    // просто остановился».
    await _guard(() => _coordinator.startQueue(startIndex: index));
  }

  /// Гарантирует, что [media] присутствует в очереди, и делает его
  /// текущим. Очередь при этом не пересобирается целиком: если трек
  /// уже играет, состояние вообще не трогаем (переоткрытие очереди
  /// ломало бы авто-переход на текущем треке).
  Future<void> playFromQueue(Media media) async {
    final index = state.items.indexWhere((m) => m.id == media.id);
    if (index >= 0) {
      if (index == state.currentIndex) return;
      await jumpTo(index);
      return;
    }
    await setQueue([...state.items, media], startIndex: state.items.length);
  }

  /// Adds a single item to the end of the queue.
  void enqueue(Media item) => enqueueAll([item]);

  /// Adds multiple items to the queue.
  void enqueueAll(List<Media> items) {
    if (items.isEmpty) return;
    state = PlayQueueState(
      items: [...state.items, ...items],
      // В пустую очередь «В очередь» ничего не запускает (как и раньше),
      // поэтому текущего трека нет: currentIndex остаётся -1, иначе
      // current и вкладка «Очередь» показывали бы трек, который не играет.
      currentIndex: state.currentIndex,
    );
    unawaited(_guard(() => _coordinator.enqueue(items)));
  }

  /// Plays the current track of the queue from the beginning.
  Future<bool> playCurrent() async {
    if (state.currentIndex < 0 || state.currentIndex >= state.items.length) {
      return false;
    }
    await _guard(_coordinator.restartCurrent);
    return true;
  }

  /// Plays the next track in the queue.
  /// Returns false if there is no next track.
  Future<bool> next() async {
    if (state.currentIndex + 1 >= state.items.length) return false;
    return await _guard(() => _coordinator.next()) ?? false;
  }

  /// Plays the previous track in the queue.
  /// Returns false if there is no previous track.
  Future<bool> previous() async {
    if (state.currentIndex <= 0) return false;
    return await _guard(() => _coordinator.previous()) ?? false;
  }

  /// Jumps to [index] in the queue. Returns false for an invalid index.
  Future<bool> jumpTo(int index) async {
    if (index < 0 || index >= state.items.length) return false;
    return await _guard(() => _coordinator.jump(index)) ?? false;
  }

  /// Removes item at [index] from the queue.
  void removeAt(int index) {
    if (index < 0 || index >= state.items.length) return;
    final items = List<Media>.from(state.items)..removeAt(index);

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

    state = PlayQueueState(items: items, currentIndex: newIndex);

    if (items.isEmpty) {
      unawaited(_coordinator.stop());
    } else {
      // Состояние уже обновлено, поэтому координатор пересоберёт
      // воспроизведение по новому currentIndex, если плейлист mpv не
      // справится сам (удаление текущего элемента).
      unawaited(_guard(() => _coordinator.removeAt(index)));
    }
  }

  /// Clears the queue and stops playback.
  void clear() {
    state = const PlayQueueState();
    unawaited(_coordinator.stop());
  }

  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, s) {
      AppLogger.error('Play queue operation failed', e, s);
      return null;
    }
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
  const new({this.items = const [], this.currentIndex = -1});

  final List<Media> items;
  final int currentIndex;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  bool get hasNext => currentIndex + 1 < items.length;
  bool get hasPrevious => currentIndex > 0;

  PlayQueueState copyWith({List<Media>? items, int? currentIndex}) {
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

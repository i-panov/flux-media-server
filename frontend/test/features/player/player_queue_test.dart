import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia([int id = 1]) => Media(
  id: id,
  title: 'Test Media $id',
  year: 2024,
  type: MediaType.audio,
  fileSize: 1024,
);

/// Fake playback controller that records calls without touching media_kit.
/// Индекс плейлиста двигается так же, как это делает mpv: отдельным
/// событием в поток, а не присваиванием из Dart.
class _FakePlaybackController implements PlaybackController {
  final indexCtl = StreamController<int>.broadcast();

  final List<int> startQueueCalls = [];
  final List<Media> enqueueCalls = [];
  final List<int> jumpCalls = [];
  final List<int> removeCalls = [];

  int stopCalls = 0;
  int restartCalls = 0;
  int index = -1;

  /// Размер плейлиста на стороне mpv: нужен фейку для клампа индекса.
  int queueLength = 0;

  void emitIndex(int value) {
    index = value;
    if (!indexCtl.isClosed) indexCtl.add(value);
  }

  @override
  Stream<int> get playlistIndexStream => indexCtl.stream;

  @override
  Future<void> startQueue({required int startIndex}) async {
    startQueueCalls.add(startIndex);
    emitIndex(startIndex);
  }

  @override
  Future<void> enqueue(List<Media> items) async {
    enqueueCalls.addAll(items);
    queueLength += items.length;
  }

  @override
  Future<bool> next() async {
    if (index + 1 >= queueLength) return false;
    emitIndex(index + 1);
    return true;
  }

  @override
  Future<bool> previous() async {
    if (index <= 0) return false;
    emitIndex(index - 1);
    return true;
  }

  @override
  Future<bool> jump(int target) async {
    jumpCalls.add(target);
    emitIndex(target);
    return true;
  }

  @override
  Future<void> removeAt(int target) async {
    removeCalls.add(target);
    queueLength = (queueLength - 1).clamp(0, 1 << 30);
    if (queueLength == 0) return;
    emitIndex(index.clamp(0, queueLength - 1));
  }

  @override
  Future<void> restartCurrent() async {
    restartCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  Future<void> disposeStreams() => indexCtl.close();
}

void main() {
  late _FakePlaybackController fakeController;
  late PlayQueueNotifier notifier;
  late ProviderContainer container;

  setUp(() {
    fakeController = _FakePlaybackController();
    container = ProviderContainer(
      overrides: [playbackControllerProvider.overrideWithValue(fakeController)],
    );
    notifier = container.read(playQueueProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await fakeController.disposeStreams();
  });

  group('PlayQueueState', () {
    test('initial state is empty', () {
      const state = PlayQueueState();
      expect(state.items, isEmpty);
      expect(state.currentIndex, -1);
    });

    test('isEmpty returns true when no items', () {
      const state = PlayQueueState();
      expect(state.isEmpty, isTrue);
    });

    test('isNotEmpty returns false when no items', () {
      const state = PlayQueueState();
      expect(state.isNotEmpty, isFalse);
    });

    test('hasNext returns true when there are more items', () {
      final state = PlayQueueState(
        items: [_fakeMedia(), _fakeMedia(2)],
        currentIndex: 0,
      );
      expect(state.hasNext, isTrue);
    });

    test('hasPrevious returns true when not at first item', () {
      final state = PlayQueueState(
        items: [_fakeMedia(), _fakeMedia(2)],
        currentIndex: 1,
      );
      expect(state.hasPrevious, isTrue);
    });
  });

  group('PlayQueueNotifier.setQueue', () {
    test('sets queue and starts playback from startIndex', () async {
      final items = [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)];
      await notifier.setQueue(items, startIndex: 1);

      expect(notifier.state.items, hasLength(3));
      expect(notifier.state.currentIndex, 1);
      // Вся очередь уходит в mpv одним вызовом, а не по треку.
      expect(fakeController.startQueueCalls, [1]);
    });

    test('setQueue with empty items does not start playback', () async {
      await notifier.setQueue([]);
      expect(notifier.state.items, isEmpty);
      expect(notifier.state.currentIndex, -1);
      expect(fakeController.startQueueCalls, isEmpty);
    });

    test('setQueue clamps startIndex above items length', () async {
      final items = [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)];
      await notifier.setQueue(items, startIndex: 5);

      expect(notifier.state.currentIndex, 2);
      expect(fakeController.startQueueCalls, [2]);
    });

    test('setQueue clamps negative startIndex to zero', () async {
      final items = [_fakeMedia(), _fakeMedia(2)];
      await notifier.setQueue(items, startIndex: -3);

      expect(notifier.state.currentIndex, 0);
      expect(fakeController.startQueueCalls, [0]);
    });
  });

  group('PlayQueueNotifier.enqueue', () {
    test('enqueue adds item to end', () async {
      await notifier.setQueue([_fakeMedia()]);
      notifier.enqueue(_fakeMedia(2));
      await _settle();

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.items[1].id, 2);
      expect(fakeController.enqueueCalls.map((m) => m.id), [2]);
    });

    test('enqueue into empty queue adds without starting playback', () async {
      // «В очередь» ничего не включает (как и в HEAD), поэтому текущего
      // трека нет: currentIndex остаётся -1. Иначе current и вкладка
      // «Очередь» показывали бы трек, который не играет.
      notifier.enqueue(_fakeMedia());
      await _settle();

      expect(notifier.state.items, hasLength(1));
      expect(notifier.state.currentIndex, -1);
      expect(notifier.current, isNull);
      expect(fakeController.startQueueCalls, isEmpty);
    });

    test('enqueueAll adds multiple items', () async {
      await notifier.setQueue([_fakeMedia()]);
      notifier.enqueueAll([_fakeMedia(2), _fakeMedia(3)]);
      await _settle();

      expect(notifier.state.items, hasLength(3));
      expect(fakeController.enqueueCalls.map((m) => m.id), [2, 3]);
    });

    test('enqueueAll into empty queue leaves currentIndex at -1', () async {
      notifier.enqueueAll([_fakeMedia(), _fakeMedia(2)]);
      await _settle();

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, -1);
    });
  });

  group('PlayQueueNotifier.next', () {
    test('next advances to next track and follows the mpv index', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2), _fakeMedia(3)]);
      fakeController
        ..queueLength = 3
        ..index = 0;

      final result = await notifier.next();
      await _settle();

      expect(result, isTrue);
      expect(notifier.state.currentIndex, 1);
    });

    test('next returns false at end of queue', () async {
      await notifier.setQueue([_fakeMedia()]);

      final result = await notifier.next();

      expect(result, isFalse);
      expect(notifier.state.currentIndex, 0);
    });
  });

  group('PlayQueueNotifier.previous', () {
    test('previous goes back and follows the mpv index', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)], startIndex: 1);
      fakeController
        ..queueLength = 2
        ..index = 1;

      final result = await notifier.previous();
      await _settle();

      expect(result, isTrue);
      expect(notifier.state.currentIndex, 0);
    });

    test('previous returns false at start of queue', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)]);

      final result = await notifier.previous();

      expect(result, isFalse);
      expect(notifier.state.currentIndex, 0);
    });
  });

  group('PlayQueueNotifier.jumpTo', () {
    test('jumps to the requested index', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2), _fakeMedia(3)]);

      final result = await notifier.jumpTo(2);
      await _settle();

      expect(result, isTrue);
      expect(fakeController.jumpCalls, [2]);
      expect(notifier.state.currentIndex, 2);
    });

    test('rejects an invalid index', () async {
      await notifier.setQueue([_fakeMedia()]);

      expect(await notifier.jumpTo(7), isFalse);
      expect(fakeController.jumpCalls, isEmpty);
    });
  });

  group('PlayQueueNotifier.removeAt', () {
    test('removing the playing track keeps the same index', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2), _fakeMedia(3)]);
      fakeController
        ..queueLength = 3
        ..index = 0;

      notifier.removeAt(0);
      await _settle();

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 0);
      expect(fakeController.removeCalls, [0]);
    });

    test('removing a track before the current shifts the index down', () async {
      await notifier.setQueue([
        _fakeMedia(),
        _fakeMedia(2),
        _fakeMedia(3),
      ], startIndex: 2);
      fakeController
        ..queueLength = 3
        ..index = 2;

      notifier.removeAt(0);
      await _settle();

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.items.first.id, 2);
    });

    test(
      'removing the only track stops playback without restarting it',
      () async {
        await notifier.setQueue([_fakeMedia()]);
        fakeController.startQueueCalls.clear();

        notifier.removeAt(0);
        await _settle();

        expect(notifier.state.items, isEmpty);
        expect(notifier.state.currentIndex, -1);
        expect(fakeController.removeCalls, isEmpty);
        expect(fakeController.stopCalls, 1);
      },
    );

    test('remove at invalid index is a no-op', () async {
      await notifier.setQueue([_fakeMedia()]);

      notifier.removeAt(5);
      await _settle();

      expect(notifier.state.items, hasLength(1));
      expect(fakeController.removeCalls, isEmpty);
    });
  });

  group('PlayQueueNotifier.clear', () {
    test('clear empties the queue', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)]);

      notifier.clear();

      expect(notifier.state.items, isEmpty);
      expect(notifier.state.currentIndex, -1);
    });

    test('clear stops playback', () async {
      await notifier.setQueue([_fakeMedia()]);
      fakeController.stopCalls = 0;

      notifier.clear();

      expect(fakeController.stopCalls, 1);
    });
  });

  group('PlayQueueNotifier.playCurrent', () {
    test('restarts the current track', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)]);

      final result = await notifier.playCurrent();

      expect(result, isTrue);
      expect(fakeController.restartCalls, 1);
    });

    test('returns false on empty queue', () async {
      final result = await notifier.playCurrent();
      expect(result, isFalse);
      expect(fakeController.restartCalls, 0);
    });
  });

  group('PlayQueueNotifier.playFromQueue', () {
    test('keeps the queue and jumps to an existing track', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)]);
      fakeController
        ..queueLength = 2
        ..index = 0;

      await notifier.playFromQueue(_fakeMedia(2));
      await _settle();

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 1);
      // Переоткрывать очередь нельзя: _onCompleted иначе прыгнул бы на
      // устаревший элемент.
      expect(fakeController.startQueueCalls, [0]);
    });

    test('does nothing when the track is already current', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)]);
      fakeController.startQueueCalls.clear();

      await notifier.playFromQueue(_fakeMedia());

      expect(fakeController.startQueueCalls, isEmpty);
      expect(fakeController.jumpCalls, isEmpty);
    });

    test('appends an unknown track and plays it', () async {
      await notifier.setQueue([_fakeMedia()]);

      await notifier.playFromQueue(_fakeMedia(2));
      await _settle();

      expect(notifier.state.items, hasLength(2));
      expect(fakeController.startQueueCalls, [0, 1]);
    });
  });

  group('PlayQueueNotifier.current', () {
    test('returns current media', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)], startIndex: 1);

      expect(notifier.current?.id, 2);
    });

    test('returns null when queue is empty', () {
      expect(notifier.current, isNull);
    });
  });

  group('PlayQueueNotifier.upcoming', () {
    test('returns items after current', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2), _fakeMedia(3)]);

      expect(notifier.upcoming, hasLength(2));
      expect(notifier.upcoming[0].id, 2);
      expect(notifier.upcoming[1].id, 3);
    });

    test('returns empty at end of queue', () async {
      await notifier.setQueue([_fakeMedia()]);

      expect(notifier.upcoming, isEmpty);
    });
  });
}

/// Settles all pending microtasks and short futures.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

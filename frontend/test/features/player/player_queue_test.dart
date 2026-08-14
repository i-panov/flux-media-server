import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia([int id = 1]) => Media(
      id: id,
      title: 'Test Media $id',
      year: 2024,
      type: MediaType.video,
      fileSize: 1024,
    );

/// Fake playback controller that records calls without touching media_kit.
class _FakePlaybackController implements PlaybackController {
  final List<Media> playCalls = [];
  int stopCalls = 0;

  @override
  Future<void> play(Media media) async {
    playCalls.add(media);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  late _FakePlaybackController fakeController;
  late PlayQueueNotifier notifier;

  setUp(() {
    fakeController = _FakePlaybackController();
    notifier = PlayQueueNotifier(fakeController);
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
      final state =
          PlayQueueState(items: [_fakeMedia(), _fakeMedia(2)], currentIndex: 0);
      expect(state.hasNext, isTrue);
    });

    test('hasPrevious returns true when not at first item', () {
      final state =
          PlayQueueState(items: [_fakeMedia(), _fakeMedia(2)], currentIndex: 1);
      expect(state.hasPrevious, isTrue);
    });
  });

  group('PlayQueueNotifier.setQueue', () {
    test('sets queue and starts playback from startIndex', () async {
      final items = [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)];
      await notifier.setQueue(items, startIndex: 1);

      expect(notifier.state.items, hasLength(3));
      expect(notifier.state.currentIndex, 1);
      expect(fakeController.playCalls, hasLength(1));
      expect(fakeController.playCalls.first.id, 2);
    });

    test('setQueue with empty items does not call play', () async {
      await notifier.setQueue([]);
      expect(notifier.state.items, isEmpty);
      expect(notifier.state.currentIndex, -1);
      expect(fakeController.playCalls, isEmpty);
    });
  });

  group('PlayQueueNotifier.enqueue', () {
    test('enqueue adds item to end', () {
      final items = [_fakeMedia()];
      notifier
        ..setQueue(items)
        ..enqueue(_fakeMedia(2));

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.items[1].id, 2);
    });

    test('enqueueAll adds multiple items', () {
      notifier
        ..setQueue([_fakeMedia()])
        ..enqueueAll([_fakeMedia(2), _fakeMedia(3)]);

      expect(notifier.state.items, hasLength(3));
    });
  });

  group('PlayQueueNotifier.next', () {
    test('next advances to next track and calls play', () async {
      final items = [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)];
      await notifier.setQueue(items);

      fakeController.playCalls.clear();
      final result = await notifier.next();

      expect(result, isTrue);
      expect(notifier.state.currentIndex, 1);
      expect(fakeController.playCalls, hasLength(1));
      expect(fakeController.playCalls.first.id, 2);
    });

    test('next returns false at end of queue', () async {
      await notifier.setQueue([_fakeMedia()]);

      fakeController.playCalls.clear();
      final result = await notifier.next();

      expect(result, isFalse);
      expect(notifier.state.currentIndex, 0);
      expect(fakeController.playCalls, isEmpty);
    });
  });

  group('PlayQueueNotifier.previous', () {
    test('previous goes back and calls play', () async {
      final items = [_fakeMedia(), _fakeMedia(2)];
      await notifier.setQueue(items, startIndex: 1);

      fakeController.playCalls.clear();
      final result = await notifier.previous();

      expect(result, isTrue);
      expect(notifier.state.currentIndex, 0);
      expect(fakeController.playCalls, hasLength(1));
      expect(fakeController.playCalls.first.id, 1);
    });

    test('previous returns false at start of queue', () async {
      await notifier.setQueue([_fakeMedia(), _fakeMedia(2)]);

      fakeController.playCalls.clear();
      final result = await notifier.previous();

      expect(result, isFalse);
      expect(fakeController.playCalls, isEmpty);
    });
  });

  group('PlayQueueNotifier.removeAt auto-advance', () {
    test('removing the playing track calls play with the next item',
        () async {
      await notifier.setQueue(
        [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)],
      );
      fakeController.playCalls.clear();

      notifier.removeAt(0);

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 0);
      expect(fakeController.playCalls, hasLength(1));
      expect(fakeController.playCalls.first.id, 2);
    });

    test('removing the playing track in the middle plays the following item',
        () async {
      await notifier.setQueue(
        [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)],
        startIndex: 1,
      );
      fakeController.playCalls.clear();

      notifier.removeAt(1);

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 1);
      expect(fakeController.playCalls, hasLength(1));
      expect(fakeController.playCalls.first.id, 3);
    });

    test('removing the playing last track plays the previous item', () async {
      await notifier.setQueue(
        [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)],
        startIndex: 2,
      );
      fakeController.playCalls.clear();

      notifier.removeAt(2);

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 1);
      expect(fakeController.playCalls, hasLength(1));
      expect(fakeController.playCalls.first.id, 2);
    });

    test('removing a non-current track does not call play', () async {
      await notifier.setQueue(
        [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)],
      );
      fakeController.playCalls.clear();

      notifier.removeAt(2);

      expect(notifier.state.items, hasLength(2));
      expect(fakeController.playCalls, isEmpty);
    });

    test('removing the only track stops playback without calling play',
        () async {
      await notifier.setQueue([_fakeMedia()]);
      fakeController.playCalls.clear();

      notifier.removeAt(0);

      expect(notifier.state.items, isEmpty);
      expect(fakeController.playCalls, isEmpty);
      expect(fakeController.stopCalls, 1);
    });
  });

  group('PlayQueueNotifier.removeAt', () {
    test('remove non-current item keeps currentIndex', () {
      notifier
        ..setQueue([_fakeMedia(), _fakeMedia(2), _fakeMedia(3)])
        ..removeAt(2); // Remove last (not current)

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 0);
    });

    test('remove item before current shifts currentIndex', () {
      notifier
        ..setQueue([_fakeMedia(), _fakeMedia(2), _fakeMedia(3)])
        ..removeAt(0); // Remove first, current is at 0

      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.currentIndex, 0);
      expect(notifier.state.items.first.id, 2);
    });

    test('remove only item stops playback', () {
      notifier
        ..setQueue([_fakeMedia()])
        ..removeAt(0);

      expect(notifier.state.items, isEmpty);
      expect(notifier.state.currentIndex, -1);
      expect(fakeController.stopCalls, 1);
    });

    test('remove at invalid index is no-op', () {
      notifier
        ..setQueue([_fakeMedia()])
        ..removeAt(5);

      expect(notifier.state.items, hasLength(1));
    });
  });

  group('PlayQueueNotifier.clear', () {
    test('clear empties the queue', () {
      notifier
        ..setQueue([_fakeMedia(), _fakeMedia(2)])
        ..clear();

      expect(notifier.state.items, isEmpty);
      expect(notifier.state.currentIndex, -1);
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
      await notifier.setQueue(
        [_fakeMedia(), _fakeMedia(2), _fakeMedia(3)],
      );

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

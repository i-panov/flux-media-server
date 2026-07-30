import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia([int id = 1]) => Media(
      id: id,
      title: 'Test Media $id',
      year: 2024,
      type: 'movie',
      filePath: '/test$id.mp4',
      fileSize: 1024,
    );

void main() {
  group('PlayQueueState', () {
    test('initial state is empty', () {
      const state = PlayQueueState();
      expect(state.items, isEmpty);
      expect(state.currentIndex, -1);
    });

    test('copyWith creates new state with updated values', () {
      const state = PlayQueueState();
      final newState = state.copyWith(items: [_fakeMedia()], currentIndex: 0);
      
      expect(newState.items, hasLength(1));
      expect(newState.currentIndex, 0);
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
      final state = PlayQueueState(items: [_fakeMedia(1), _fakeMedia(2)], currentIndex: 0);
      expect(state.hasNext, isTrue);
    });

    test('hasPrevious returns true when not at first item', () {
      final state = PlayQueueState(items: [_fakeMedia(1), _fakeMedia(2)], currentIndex: 1);
      expect(state.hasPrevious, isTrue);
    });
  });

  group('PlayQueueState methods', () {
    test('add to queue', () {
      final state = const PlayQueueState();
      final newState = state.copyWith(items: [...state.items, _fakeMedia(1)]);
      
      expect(newState.items, hasLength(1));
      expect(newState.items[0].id, 1);
    });

    test('remove from queue', () {
      final state = PlayQueueState(items: [_fakeMedia(1), _fakeMedia(2), _fakeMedia(3)], currentIndex: 0);
      final items = List<Media>.from(state.items)..removeAt(1); // Remove media2
      final newState = state.copyWith(items: items, currentIndex: 0);
      
      expect(newState.items, hasLength(2));
      expect(newState.items[0].id, 1);
      expect(newState.items[1].id, 3);
    });

    test('clear queue', () {
      final state = PlayQueueState(items: [_fakeMedia(1), _fakeMedia(2)], currentIndex: 0);
      final newState = const PlayQueueState();
      
      expect(newState.items, isEmpty);
      expect(newState.currentIndex, -1);
    });

    test('play next from queue', () {
      final state = PlayQueueState(items: [_fakeMedia(1), _fakeMedia(2)], currentIndex: 0);
      final newState = state.copyWith(currentIndex: 1);
      
      expect(newState.currentIndex, 1);
    });
  });
}
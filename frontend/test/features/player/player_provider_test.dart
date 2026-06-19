import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/presentation/providers/player_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia() => const Media(
      id: 1,
      title: 'Test Media',
      year: 2024,
      type: 'movie',
      filePath: '/test.mp4',
      fileSize: 1024,
    );

void main() {
  group('PlayerNotifierState', () {
    test('initial state', () {
      const state = PlayerNotifierState.initial();
      expect(state, isA<PlayerNotifierInitial>());
    });

    test('playing state with media', () {
      final media = _fakeMedia();
      final state = PlayerNotifierState.playing(media: media);
      expect(state, isA<PlayerNotifierPlaying>());
      expect((state as PlayerNotifierPlaying).media.id, 1);
      expect(state.isPaused, false);
      expect(state.position, Duration.zero);
    });

    test('completed state', () {
      const state = PlayerNotifierState.completed();
      expect(state, isA<PlayerNotifierCompleted>());
    });

    test('error state contains message', () {
      const state = PlayerNotifierState.error(message: 'test error');
      expect(state, isA<PlayerNotifierError>());
      expect((state as PlayerNotifierError).message, 'test error');
    });

    test('playing state copyWith', () {
      final media = _fakeMedia();
      final state = PlayerNotifierState.playing(media: media) as PlayerNotifierPlaying;
      final updated = state.copyWith(
        isPaused: true,
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 2),
      );

      expect(updated.isPaused, true);
      expect(updated.position, const Duration(seconds: 30));
      expect(updated.duration, const Duration(minutes: 2));
    });
  });
}

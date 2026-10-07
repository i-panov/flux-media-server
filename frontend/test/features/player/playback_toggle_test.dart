import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/presentation/utils/playback_toggle.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _media(int id) =>
    Media(id: id, title: 'T$id', type: MediaType.video, fileSize: 1);

/// Координатор с фиксированным состоянием: реальные pause/resume только
/// считают вызовы, потоки плеера не поднимаются.
class _FixedCoordinator extends PlaybackCoordinator {
  new(this.fixed);

  final PlaybackState fixed;
  int paused = 0;
  int resumed = 0;

  @override
  PlaybackState build() => fixed;

  @override
  Future<void> pause() async {
    paused++;
  }

  @override
  Future<void> resume() async {
    resumed++;
  }
}

class _Tapper extends ConsumerWidget {
  const new({required this.mediaId, this.isPaused = false, this.onStartOther});

  final int mediaId;
  final bool isPaused;
  final void Function(int mediaId)? onStartOther;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => togglePlayback(
        ref,
        mediaId,
        isPaused: isPaused,
        onStartOther: onStartOther,
      ),
      child: const Text('tap'),
    );
  }
}

void main() {
  const step = Duration(seconds: 10);

  group('clampSeekPosition', () {
    test('перемотка назад с начала упирается в ноль', () {
      expect(
        clampSeekPosition(
          position: const Duration(seconds: 3),
          step: -step,
          duration: const Duration(minutes: 10),
        ),
        Duration.zero,
      );
    });

    test('перемотка вперёд за конец упирается в длительность', () {
      const duration = Duration(minutes: 10);
      expect(
        clampSeekPosition(
          position: const Duration(minutes: 9, seconds: 55),
          step: step,
          duration: duration,
        ),
        duration,
      );
    });

    test('обычная перемотка не меняется', () {
      expect(
        clampSeekPosition(
          position: const Duration(minutes: 5),
          step: step,
          duration: const Duration(minutes: 10),
        ),
        const Duration(minutes: 5, seconds: 10),
      );
    });

    test('без известной длительности ограничиваемся только снизу', () {
      expect(
        clampSeekPosition(
          position: const Duration(minutes: 5),
          step: const Duration(hours: 2),
          duration: Duration.zero,
        ),
        const Duration(hours: 2, minutes: 5),
      );
      expect(
        clampSeekPosition(
          position: const Duration(seconds: 3),
          step: -step,
          duration: Duration.zero,
        ),
        Duration.zero,
      );
    });
  });

  group('togglePlayback', () {
    Future<_FixedCoordinator> pumpTapper(
      WidgetTester tester,
      PlaybackState state, {
      required int mediaId,
      bool isPaused = false,
      void Function(int mediaId)? onStartOther,
    }) async {
      final coordinator = _FixedCoordinator(state);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackCoordinatorProvider.overrideWith(() => coordinator),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _Tapper(
                mediaId: mediaId,
                isPaused: isPaused,
                onStartOther: onStartOther,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pump();
      return coordinator;
    }

    testWidgets('тап по своему играющему треку ставит на паузу', (
      tester,
    ) async {
      final coordinator = await pumpTapper(
        tester,
        PlaybackPlaying(media: _media(1), type: MediaType.video),
        mediaId: 1,
      );
      expect(coordinator.paused, 1);
      expect(coordinator.resumed, 0);
    });

    testWidgets('тап по своему треку на паузе продолжает', (tester) async {
      final coordinator = await pumpTapper(
        tester,
        PlaybackPlaying(
          media: _media(1),
          type: MediaType.video,
          isPaused: true,
        ),
        mediaId: 1,
        isPaused: true,
      );
      expect(coordinator.resumed, 1);
      expect(coordinator.paused, 0);
    });

    testWidgets('тап по чужому треку уходит в onStartOther', (tester) async {
      int? started;
      final coordinator = await pumpTapper(
        tester,
        PlaybackPlaying(media: _media(2), type: MediaType.video),
        mediaId: 1,
        onStartOther: (id) => started = id,
      );
      expect(started, 1);
      expect(coordinator.paused, 0);
      expect(coordinator.resumed, 0);
    });

    testWidgets('нет текущего трека и колбэка — не падает', (tester) async {
      final coordinator = await pumpTapper(
        tester,
        const PlaybackState.initial(),
        mediaId: 1,
      );
      expect(coordinator.paused, 0);
      expect(coordinator.resumed, 0);
    });

    testWidgets('stale-кадр без колбэка переключает реальный трек', (
      tester,
    ) async {
      final coordinator = await pumpTapper(
        tester,
        PlaybackPlaying(media: _media(2), type: MediaType.video),
        mediaId: 1,
      );
      expect(coordinator.paused, 1);
      expect(coordinator.resumed, 0);
    });
  });
}

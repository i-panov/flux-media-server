import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_view.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_player_panel.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _video(int id) => Media(
  id: id,
  title: 'Video $id',
  type: MediaType.video,
  fileSize: 1,
);

Media _track(int id) => Media(
  id: id,
  title: 'Track $id',
  type: MediaType.audio,
  fileSize: 1,
);

void main() {
  group('shouldPauseOnPanelDispose', () {    test('своё играющее видео — пауза', () {
      expect(
        shouldPauseOnPanelDispose(
          PlaybackState.playing(media: _video(7), type: MediaType.video),
          7,
        ),
        isTrue,
      );
    });

    test('чужое видео — не трогаем (его панель сама разберётся)', () {
      expect(
        shouldPauseOnPanelDispose(
          PlaybackState.playing(media: _video(9), type: MediaType.video),
          7,
        ),
        isFalse,
      );
    });

    test('фоновое аудио — не трогаем', () {
      expect(
        shouldPauseOnPanelDispose(
          PlaybackState.playing(media: _track(3), type: MediaType.audio),
          3,
        ),
        isFalse,
      );
    });

    test('уже на паузе / не играет — не трогаем', () {
      expect(
        shouldPauseOnPanelDispose(
          PlaybackState.playing(
            media: _video(7),
            type: MediaType.video,
            isPaused: true,
          ),
          7,
        ),
        isFalse,
      );
      expect(
        shouldPauseOnPanelDispose(const PlaybackState.initial(), 7),
        isFalse,
      );
      expect(
        shouldPauseOnPanelDispose(const PlaybackState.completed(), 7),
        isFalse,
      );
      expect(
        shouldPauseOnPanelDispose(const PlaybackState.loading(), 7),
        isFalse,
      );
      expect(
        shouldPauseOnPanelDispose(
          const PlaybackState.error(message: 'boom'),
          7,
        ),
        isFalse,
      );
    });
  });

  group('showResumeControl', () {
    test('только играющее видео с позицией', () {
      expect(
        showResumeControl(
          PlayerViewKind.playing,
          MediaType.video,
          const Duration(seconds: 30),
        ),
        isTrue,
      );
    });

    test('без позиции, не видео, не playing — скрыта', () {
      expect(
        showResumeControl(PlayerViewKind.playing, MediaType.video, null),
        isFalse,
      );
      expect(
        showResumeControl(
          PlayerViewKind.playing,
          MediaType.audio,
          const Duration(seconds: 30),
        ),
        isFalse,
      );
      expect(
        showResumeControl(
          PlayerViewKind.initial,
          MediaType.video,
          const Duration(seconds: 30),
        ),
        isFalse,
      );
    });
  });
}

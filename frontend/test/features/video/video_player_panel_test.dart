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
  group('shouldPauseOnScreenDispose', () {
    // Регрессия (P0): вход в полный экран ставил видео на паузу.
    //
    // Экран собирает две разные ветви дерева (встроенная и полноэкранная),
    // поэтому панель при смене режима пересоздаётся, и её dispose
    // срабатывал. Пауза в dispose панели останавливала видео ровно в
    // момент входа в полный экран — пользователь видел застывший кадр.
    //
    // Теперь пауза живёт на экране: его dispose — это настоящий уход,
    // а смена режима экран не трогает.
    test('своё играющее видео — пауза при уходе с экрана', () {
      expect(
        shouldPauseOnScreenDispose(
          PlaybackState.playing(media: _video(7), type: MediaType.video),
          7,
        ),
        isTrue,
      );
    });

    test('на паузе, чужое видео, аудио — не трогаем', () {
      expect(
        shouldPauseOnScreenDispose(
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
        shouldPauseOnScreenDispose(
          PlaybackState.playing(media: _video(9), type: MediaType.video),
          7,
        ),
        isFalse,
      );
      expect(
        shouldPauseOnScreenDispose(
          PlaybackState.playing(media: _track(7), type: MediaType.audio),
          7,
        ),
        isFalse,
      );
      expect(
        shouldPauseOnScreenDispose(const PlaybackState.initial(), 7),
        isFalse,
      );
    });
  });

  group('shouldPauseOnPanelDispose', () {
    test('своё играющее видео — пауза', () {
      expect(
        shouldPauseOnPanelDispose(
          PlaybackState.playing(media: _video(7), type: MediaType.video),
          7,
        ),
        isTrue,
      );
    });

    test('на паузе, чужое видео, аудио — не трогаем', () {
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
        shouldPauseOnPanelDispose(
          PlaybackState.playing(media: _video(9), type: MediaType.video),
          7,
        ),
        isFalse,
      );
      expect(
        shouldPauseOnPanelDispose(
          PlaybackState.playing(media: _track(7), type: MediaType.audio),
          7,
        ),
        isFalse,
      );
      expect(
        shouldPauseOnPanelDispose(const PlaybackState.initial(), 7),
        isFalse,
      );
    });
  });

  group('isOwnPlayingVideo', () {
    PlayerView playing(int id) => PlayerView(
      kind: PlayerViewKind.playing,
      media: _video(id),
      type: MediaType.video,
      isPaused: false,
      errorMessage: null,
    );

    test('своё играющее видео — живой кадр', () {
      expect(isOwnPlayingVideo(playing(7), 7), isTrue);
    });

    test('пауза своего видео — тоже живой кадр', () {
      // Кнопка play поверх превью на паузе показывается, но сам кадр
      // остаётся: это и есть точка, с которой видео продолжится.
      expect(
        isOwnPlayingVideo(
          PlayerView(
            kind: PlayerViewKind.playing,
            media: _video(7),
            type: MediaType.video,
            isPaused: true,
            errorMessage: null,
          ),
          7,
        ),
        isTrue,
      );
    });

    test('чужое видео и не-playing — постер', () {
      expect(isOwnPlayingVideo(playing(9), 7), isFalse);
      expect(
        isOwnPlayingVideo(
          const PlayerView(
            kind: PlayerViewKind.initial,
            media: null,
            type: null,
            isPaused: false,
            errorMessage: null,
          ),
          7,
        ),
        isFalse,
      );
      expect(
        isOwnPlayingVideo(
          const PlayerView(
            kind: PlayerViewKind.completed,
            media: null,
            type: null,
            isPaused: false,
            errorMessage: null,
          ),
          7,
        ),
        isFalse,
      );
    });
  });
}

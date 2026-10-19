import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/utils/video_geometry.dart';

void main() {
  group('videoOrientationFor', () {
    test('горизонтальное видео — альбомная', () {
      expect(
        videoOrientationFor(width: 1920, height: 1080),
        VideoOrientation.landscape,
      );
      expect(
        videoOrientationFor(width: 720, height: 576),
        VideoOrientation.landscape,
      );
    });

    test('вертикальный ролик — книжная', () {
      expect(
        videoOrientationFor(width: 1080, height: 1920),
        VideoOrientation.portrait,
      );
    });

    test('квадратное — альбомная (полосы одинаковы, привычнее альбом)', () {
      expect(
        videoOrientationFor(width: 1080, height: 1080),
        VideoOrientation.landscape,
      );
    });

    test('без размеров — unknown, а не догадка по типу', () {
      // Старые записи до бэкфилла: выбирать ориентацию не из чего.
      expect(videoOrientationFor(width: 0, height: 0), VideoOrientation.unknown);
      expect(
        videoOrientationFor(width: 1920, height: 0),
        VideoOrientation.unknown,
      );
      expect(
        videoOrientationFor(width: -1, height: 1080),
        VideoOrientation.unknown,
      );
    });
  });

  group('orientationsFor', () {
    test('альбомная — в обе стороны, телефон можно перевернуть', () {
      expect(
        orientationsFor(VideoOrientation.landscape),
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    });

    test('книжная — вверх и вниз (снизу динамик, зеркало не нужно)', () {
      expect(
        orientationsFor(VideoOrientation.portrait),
        const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
      );
    });

    test('без размеров — альбомная: лучше угадать с большинством', () {
      expect(
        orientationsFor(VideoOrientation.unknown),
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    });
  });

  group('videoAspectRatioFor', () {
    test('берёт реальные пропорции кадра', () {
      expect(videoAspectRatioFor(width: 1920, height: 1080), 16 / 9);
      expect(videoAspectRatioFor(width: 1080, height: 1920), 1080 / 1920);
      expect(videoAspectRatioFor(width: 4, height: 3), 4 / 3);
    });

    test('без размеров и при мусоре — 16:9', () {
      expect(videoAspectRatioFor(width: 0, height: 0), 16 / 9);
      expect(videoAspectRatioFor(width: 1920, height: 0), 16 / 9);
      // Повреждённые метаданные не должны растянуть превью в столбик
      // на весь экран.
      expect(videoAspectRatioFor(width: 1, height: 10000), 16 / 9);
      expect(videoAspectRatioFor(width: 10000, height: 1), 16 / 9);
    });
  });
}

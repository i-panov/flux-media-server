import 'package:flutter/services.dart';

/// Ориентация экрана в полноэкранном режиме плеера.
///
/// Выбор делается по размерам кадра, которые сервер отдаёт при скане
/// и загрузке (ffprobe). Без них остаётся альбомная: подавляющее
/// большинство видео горизонтальные, а в вертикальном ролике телефон
/// просто покажет чёрные поля по бокам — не хуже, чем наоборот.
///
/// Ориентации не «фиксируются» в настройках видео намеренно: это лишнее
/// состояние ради случая, который детектится автоматически.
enum VideoOrientation {
  /// Горизонтальная: альбомная в обе стороны.
  landscape,

  /// Вертикальная: книжная вверх.
  portrait,

  /// Размеры неизвестны (старые записи, аудио, файл без видеопотока).
  unknown,
}

/// Определяет ориентацию по размерам кадра в пикселях.
///
/// Квадратное видео (width == height) считается горизонтальным: при равенстве
/// сторон полосы одинаковы в обеих ориентациях, а альбомная всё равно
/// привычнее для просмотра.
VideoOrientation videoOrientationFor({required int width, required int height}) {
  if (width <= 0 || height <= 0) return VideoOrientation.unknown;
  if (width == height) return VideoOrientation.landscape;
  return width > height ? VideoOrientation.landscape : VideoOrientation.portrait;
}

/// Ориентации, которые просим у системы для [VideoOrientation].
///
/// Для [VideoOrientation.unknown] — альбомная: лучше угадать с
/// подавляющим большинством, чем оставить телефон в книжной и
/// обрезать по краям горизонтальный кадр.
List<DeviceOrientation> orientationsFor(VideoOrientation orientation) {
  switch (orientation) {
    case VideoOrientation.landscape:
    case VideoOrientation.unknown:
      return const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];
    case VideoOrientation.portrait:
      return const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ];
  }
}

/// Пропорции кадра для встроенного превью.
///
/// Без размеров — 16:9 (самый частый случай для старых записей), а не
/// 4:3: картинка будет чуть обрезана по бокам, но не окажется
/// вытянутой по вертикали.
double videoAspectRatioFor({required int width, required int height}) {
  if (width <= 0 || height <= 0) return 16 / 9;
  final ratio = width / height;
  // Без клампа: повреждённые метаданные (1x10000) растянули бы превью
  // в столбик на весь экран.
  if (ratio < 0.3 || ratio > 4) return 16 / 9;
  return ratio;
}

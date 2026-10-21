import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Включить или снять флаг «не гасить экран».
typedef WakelockApply = Future<void> Function({required bool enable});

/// Держит экран включённым, пока видео играет на переднем плане.
///
/// media_kit_video умеет wakelock сам, но привязывает его только к потоку
/// `playing` и о lifecycle приложения не знает: в свёрнутом состоянии флаг
/// оставался включённым, хотя экран всё равно выключен, а на iOS
/// отключённый idle timer не давал устройству уснуть — то есть фоновое
/// воспроизведение съедало батарею.
///
/// Поэтому управляем сами: у Video виджета wakelock выключен, а решение
/// принимает экран — он переживает смену режима (встроенная ⇄ полный
/// экран) и знает, когда приложение ушло в фон.
class VideoWakelock {
  /// Wakelock поверх настоящего флага устройства.
  factory() => VideoWakelock._(_applyOnDevice);

  /// Wakelock с подменённым применением флага — для тестов.
  @visibleForTesting
  factory forTest(WakelockApply apply) => VideoWakelock._(apply);

  new _(this._apply);

  final WakelockApply _apply;

  /// Приложение на переднем плане.
  bool _foreground = true;

  /// Видео играет.
  bool _playing = false;

  /// Состояние флага на устройстве — чтобы не дёргать платформу повторно.
  bool _enabled = false;

  /// Сообщить, что видео играет (или остановилось).
  void updatePlaying({required bool playing}) {
    if (_playing == playing) return;
    _playing = playing;
    _sync();
  }

  /// Сообщить, что приложение ушло в фон или вернулось.
  void updateForeground({required bool foreground}) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _sync();
  }

  /// Снять флаг. Вызывается при уходе с экрана видео.
  void dispose() {
    if (!_enabled) return;
    _enabled = false;
    unawaited(_apply(enable: false));
  }

  void _sync() {
    final shouldHold = _foreground && _playing;
    if (shouldHold == _enabled) return;
    _enabled = shouldHold;
    unawaited(_apply(enable: shouldHold));
  }
}

/// Применить флаг на устройстве.
///
/// Ошибка платформы не должна ронять приложение: «не гасить экран» — вещь
/// второго порядка, видео должно играть и без него.
Future<void> _applyOnDevice({required bool enable}) async {
  try {
    if (enable) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  } catch (_) {
    // Платформа не поддержала флаг — работаем без него.
  }
}

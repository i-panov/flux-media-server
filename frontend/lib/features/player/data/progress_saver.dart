import 'dart:async';
import 'dart:developer' as developer;

import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';

/// Сохранение прогресса просмотра на сервер.
///
/// Выделено из `PlaybackCoordinator`: ему принадлежали и цепочка
/// сохранений, и таймер автосохранения, и чтение позиции — хотя
/// координатор отвечает за маршрутизацию воспроизведения, а не за
/// персистентность. Граница:
///
/// - вход — только значения (`mediaId`, `position`, `duration`), никакого
///   `PlaybackState` и Riverpod внутри;
/// - таймер дёргает снимок через колбэк, который даёт координатор;
/// - все ошибки глотаются (best-effort): несoхранённый прогресс —
///   не повод ронять воспроизведение.
class ProgressSaver {
  new({
    required this.repository,
    this.saveInterval = const Duration(seconds: 10),
  });

  final MediaRepository repository;

  /// Интервал автосохранения прогресса во время воспроизведения.
  final Duration saveInterval;

  /// Сериализует сохранения прогресса: параллельные вызовы (completed
  /// при завершении трека, save таймера, сохранения предыдущего трека
  /// при переключении) выполняются строго по очереди, чтобы более
  /// позднее сохранение не перезаписало более раннее (гонка
  /// completed:true vs completed:false).
  Future<void> _saveChain = Future.value();

  Timer? _timer;

  /// Saves watch progress to the backend. Best-effort: errors are logged
  /// and ignored. Отправляет duration и completed — бэкенд их принимает
  /// и сохраняет. Вызовы сериализуются через [_saveChain].
  Future<void> save(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) {
    final result = _saveChain.then(
      (_) => _doSave(mediaId, position, duration, completed: completed),
    );
    _saveChain = result.catchError((_) {});
    return result;
  }

  Future<void> _doSave(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) async {
    if (position <= Duration.zero) return;
    try {
      await repository.updateProgress(
        mediaId,
        position: position.inSeconds,
        duration: duration.inSeconds,
        completed: completed ?? false,
      );
    } on Exception catch (e) {
      developer.log('Failed to save progress: $e');
    }
  }

  /// Periodically persists the snapshot provided by [current] while
  /// playing. Предыдущий таймер гасится: одновременно живёт только один.
  void startAutoSave(
    ({int mediaId, Duration position, Duration duration})? Function() current,
  ) {
    stopAutoSave();
    _timer = Timer.periodic(saveInterval, (_) {
      final snap = current();
      if (snap == null) return;
      unawaited(save(snap.mediaId, snap.position, snap.duration));
    });
  }

  /// Останавливает автосохранение. Вызывать при паузе/остановке/
  /// переключении трека и при dispose владельца.
  void stopAutoSave() {
    _timer?.cancel();
    _timer = null;
  }
}

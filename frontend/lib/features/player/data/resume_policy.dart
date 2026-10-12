import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';

/// Политика resume для видео: порог, загрузка сохранённой позиции
/// и решение «показать диалог vs применить молча».
///
/// Выделено из `PlaybackCoordinator`: порог и разбор сохранённой позиции
/// — чистое правило без зависимости от плееров и состояния. Граница:
///
/// - вход — сохранённая позиция (или её отсутствие);
/// - выход — что показать в оверлее и куда мотать сразу.
class ResumePolicy {
  new({required this.repository});

  final MediaRepository repository;

  /// Порог для resume-оверлея: позиции не больше этого значения
  /// применяются сразу (видео продолжается без диалога).
  static const threshold = Duration(seconds: 5);

  /// Returns the saved watch position for [mediaId], or null if there is
  /// none (or the media was already completed).
  Future<Duration?> loadSavedPosition(int mediaId) async {
    final result = await repository.getProgress();
    return await result.fold((_) async => null, (progressList) async {
      for (final p in progressList) {
        if (p.mediaId == mediaId && p.position > 0) {
          return Duration(seconds: p.position);
        }
      }
      return null;
    });
  }

  /// Раскладывает сохранённую позицию на два действия.
  ///
  /// - `overlay`: показать в resume-диалоге (позиция больше порога);
  /// - `autoSeek`: применить молча (позиция в пределах порога).
  /// При `null` на входе оба выхода `null` — начинать с нуля.
  ///
  /// Статика осознанно: чистая функция без состояния и зависимостей,
  /// граничные условия порога тестируются без репозитория.
  static ({Duration? overlay, Duration? autoSeek}) split(Duration? saved) {
    if (saved == null) return (overlay: null, autoSeek: null);
    if (saved > threshold) return (overlay: saved, autoSeek: null);
    return (overlay: null, autoSeek: saved);
  }
}

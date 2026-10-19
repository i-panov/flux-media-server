import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';

/// Политика resume для видео: порог и загрузка сохранённой позиции.
///
/// Выделено из `PlaybackCoordinator`: порог и разбор сохранённой позиции
/// — чистое правило без зависимости от плееров и состояния. Граница:
///
/// - вход — сохранённая позиция (или её отсутствие);
/// - выход — с какой секунды продолжать (или null = с начала).
///
/// Раньше здесь был выбор «показать кнопку resume или применить молча».
/// Он и породил жалобу «жму play, а начинается сначала»: кнопка жила
/// в контролах, которые сами скрываются по таймеру, поэтому её то видели,
/// то нет. Теперь позиция применяется сразу и всегда.
class ResumePolicy {
  new({required this.repository});

  final MediaRepository repository;

  /// Порог осмысленности: с позиции не больше этого значения
  /// перемотка бессмысленна — mpv стартует там же практически.
  /// Всё, что выше, применяется автоматически.
  static const threshold = Duration(seconds: 5);

  /// Returns the saved watch position for [mediaId], or null if there is
  /// none (or the media was already completed).
  ///
  /// Точечный запрос, а не весь список: вызывается перед стартом каждого
  /// видео, и лишний трафик здесь — задержка воспроизведения.
  Future<Duration?> loadSavedPosition(int mediaId) {
    return repository.getProgressById(mediaId).then(
      (result) => result.fold((_) => null, (progress) {
        if (progress == null || progress.position <= 0) return null;
        // Досмотренное видео открываем с начала: иначе «продолжение»
        // прыгало бы в последнюю секунду и сразу останавливалось.
        // Проверка была задокументирована, но не сделана — из-за этого
        // авторезюм (теперь он всегда применяется) подводил бы к концу.
        if (progress.completed) return null;
        return Duration(seconds: progress.position);
      }),
    );
  }

  /// Позиция, с которой продолжать видео, либо null — начинать с нуля.
  ///
  /// Сохранённая позиция применяется всегда, без диалогов и кнопок:
  /// пользователь сам промотает на начало, если нужно. Значения не выше
  /// [threshold] отбрасываются — перемотка на пару секунд не стоит
  /// лишнего seek.
  ///
  /// Статика осознанно: чистая функция без состояния и зависимостей,
  /// граничные условия порога тестируются без репозитория.
  static Duration? target(Duration? saved) {
    if (saved == null || saved <= threshold) return null;
    return saved;
  }
}

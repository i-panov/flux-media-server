/// Типизированное редактирование метаданных медиа.
///
/// Заменяет «сырой» `Map<String, dynamic>`, который раньше протекал
/// через domain-слой. Маппинг в JSON выполняется в data-слое.
class MetadataEdit {
  const new({
    required this.title,
    required this.artists,
    this.album,
    this.genre,
    this.year,
    this.description,
    this.sourceUrl,
  });

  final String title;
  final List<String> artists;
  final String? album;
  final String? genre;
  final int? year;
  final String? description;

  /// Ссылка на источник. `null` — не трогать (в т.ч. без изменений),
  /// пустая строка — очистить. Отличие от album/genre осознанное: пустое
  /// поле ссылки в диалоге обязано стираться на сервере, а не
  /// игнорироваться.
  ///
  /// UI ссылки — только видео-панель (`VideoDetailsPanel`): задать ссылку
  /// можно и для аудио (диалог общий), но увидеть — только у видео.
  /// Несогласованность с `description` (пусто = null = не очистить)
  /// историческая и зафиксирована здесь, чтобы не чинить молча:
  /// менять поведение description — отдельная задача.
  final String? sourceUrl;
}

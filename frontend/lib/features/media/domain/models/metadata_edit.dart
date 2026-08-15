/// Типизированное редактирование метаданных медиа.
///
/// Заменяет «сырой» `Map<String, dynamic>`, который раньше протекал
/// через domain-слой. Маппинг в JSON выполняется в data-слое.
class MetadataEdit {
  const MetadataEdit({
    required this.title,
    required this.artists,
    this.album,
    this.genre,
    this.year,
    this.description,
  });

  final String title;
  final List<String> artists;
  final String? album;
  final String? genre;
  final int? year;
  final String? description;
}

/// Итог групповой операции с элементами коллекции.
///
/// Частичный успех — норма: часть элементов может уже лежать в целевой
/// коллекции (или её не быть), и из-за одного такого элемента весь
/// запрос падать не должен.
class BulkItemsResult {
  const new({
    this.added = const [],
    this.moved = const [],
    this.removed = const [],
    this.skipped = const [],
  });

  /// Разбор ответа сервера: списки приходят массивами чисел.
  factory parse(Map<String, dynamic> json) {
    List<int> ids(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return [
        for (final v in raw)
          if (v is int) v,
      ];
    }

    return BulkItemsResult(
      added: ids('added'),
      moved: ids('moved'),
      removed: ids('removed'),
      skipped: ids('skipped'),
    );
  }

  /// Добавленные в коллекцию элементы.
  final List<int> added;

  /// Перенесённые в другую коллекцию элементы.
  final List<int> moved;

  /// Убранные из коллекции элементы.
  final List<int> removed;

  /// Пропущенные элементы: дубликаты, отсутствующие медиа, чужие.
  final List<int> skipped;

  /// Сколько элементов реально изменилось.
  int get changedCount => added.length + moved.length + removed.length;
}

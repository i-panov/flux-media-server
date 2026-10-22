import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Выделенные медиа: id-шники.
///
/// Живёт в провайдере, а не в состоянии экрана: список показан в
/// нескольких секциях (избранное, недавние, сетка), и выделение должно
/// переживать перестройку дерева.
class MediaSelectionNotifier extends Notifier<Set<int>> {
  // Riverpod 3: family-аргумент приходит через конструктор.
  new(this.scope);

  /// Область выделения: тип медиа ('video'/'audio') или конкретная
  /// коллекция ('collection:5'). Разные области не путаются: выделение
  /// в библиотеке и выделение внутри коллекции — разные вещи.
  final String scope;

  @override
  Set<int> build() => const {};

  /// Выделен ли элемент.
  bool contains(int mediaId) => state.contains(mediaId);

  /// Переключить выделение элемента.
  void toggle(int mediaId) {
    final next = {...state};
    if (!next.remove(mediaId)) next.add(mediaId);
    state = next;
  }

  /// Снять выделение.
  void clear() => state = const {};
}

/// Выделение по области: [MediaSelectionNotifier.scope].
final mediaSelectionProvider =
    NotifierProvider.family<MediaSelectionNotifier, Set<int>, String>(
      MediaSelectionNotifier.new,
    );

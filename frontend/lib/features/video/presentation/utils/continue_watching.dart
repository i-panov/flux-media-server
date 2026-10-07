import 'package:flux_media_server/features/video/presentation/utils/watch_progress.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// Разобранный прогресс просмотра, приведённый к текущему списку медиа.
///
/// Считается ОДИН раз на экран: раньше один и тот же фильтр
/// `shouldShowInContinueWatching` прогонялся в четырёх секциях
/// `video_screen`, то есть четыре раза за rebuild.
class ContinueWatching {
  const new({required this.ids, required this.entries, required this.byId});

  /// Собирает секцию «Продолжить просмотр» для [mediaItems].
  ///
  /// Записи, чьё медиа отсутствует в списке, отбрасываются; длительность
  /// берётся из прогресса, а при нуле — из карточки.
  factory build(List<Media> mediaItems, List<WatchProgress> progress) {
    if (progress.isEmpty || mediaItems.isEmpty) {
      return ContinueWatching.empty;
    }
    final mediaById = {for (final m in mediaItems) m.id: m};
    final shown =
        progress.where((p) => mediaById.containsKey(p.mediaId)).where((p) {
          final media = mediaById[p.mediaId];
          final duration = p.duration > 0 ? p.duration : (media?.duration ?? 0);
          return shouldShowInContinueWatching(
            position: p.position,
            duration: duration,
            completed: p.completed,
          );
        }).toList()..sort(
          (a, b) =>
              _byNewestFirst(b.updatedAt)
                  .compareTo(_byNewestFirst(a.updatedAt)),
        );
    if (shown.isEmpty) return ContinueWatching.empty;
    return ContinueWatching(
      ids: {for (final p in shown) p.mediaId},
      entries: [
        for (final p in shown) (media: mediaById[p.mediaId]!, progress: p),
      ],
      byId: {for (final p in shown) p.mediaId: p},
    );
  }

  /// Пустая секция: ничего не досмотрено.
  static const empty = ContinueWatching(ids: {}, entries: [], byId: {});

  /// id медиа из секции «Продолжить просмотр».
  final Set<int> ids;

  /// Те же записи, отсортированные по свежести, с раскрытым Media.
  final List<({Media media, WatchProgress progress})> entries;

  /// Прогресс по id — для подложки карточек.
  final Map<int, WatchProgress> byId;

  bool get isEmpty => ids.isEmpty;

  /// Первые [limit] записей для показа.
  List<({Media media, WatchProgress progress})> take(int limit) =>
      entries.length <= limit ? entries : entries.sublist(0, limit);

  static DateTime _byNewestFirst(DateTime? updatedAt) =>
      updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// Делит [items] на видимую часть (первые [limit]) и остаток.
///
/// Единое место правила «свернутой» секции: раньше лимит дублировался в
/// геттерах `_LibraryData` и в `_VideoSection`, и они расходились — кнопка
/// «показать все» не появлялась, а остаток уезжал в общую сетку.
({List<T> visible, List<T> rest}) splitSection<T>(List<T> items, int limit) {
  if (items.length <= limit) return (visible: items, rest: <T>[]);
  return (visible: items.sublist(0, limit), rest: items.sublist(limit));
}

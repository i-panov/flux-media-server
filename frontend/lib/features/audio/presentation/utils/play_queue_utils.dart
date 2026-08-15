import 'package:flux_media_server/shared/models/media.dart';

/// Строит очередь воспроизведения для [media].
///
/// - [fullQueue] — полный загруженный список; если он передан, используется
///   он, иначе [fallbackQueue] (в офлайне — только скачанные треки).
/// - Если трек отсутствует в очереди, он вставляется в начало — раньше
///   вместо него молча проигрывался трек №0.
({List<Media> queue, int startIndex}) buildPlayQueue({
  required Media media,
  required List<Media> fallbackQueue,
  List<Media>? fullQueue,
}) {
  final queue = (fullQueue ?? fallbackQueue).toList();
  var index = queue.indexWhere((m) => m.id == media.id);
  if (index < 0) {
    queue.insert(0, media);
    index = 0;
  }
  return (queue: queue, startIndex: index);
}

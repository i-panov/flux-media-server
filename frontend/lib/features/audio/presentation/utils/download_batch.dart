import 'package:flux_media_server/shared/models/media.dart';

/// Результат пакетной загрузки.
typedef TrackDownloadResult = ({int downloaded, int failed});

/// Оставляет только треки, которых ещё нет в офлайн-кеше
/// (чтобы счётчик прогресса считал только фактически скачиваемые).
Future<List<Media>> filterUncachedTracks(
  List<Media> tracks,
  Future<bool> Function(int mediaId) isCached,
) async {
  final result = <Media>[];
  for (final track in tracks) {
    if (await isCached(track.id)) continue;
    result.add(track);
  }
  return result;
}

/// Скачивает [pending] треки с ограничением конкурентности.
///
/// Исключение из [download] не роняет всю пачку (CRITICAL #20): сбой
/// учитывается в поле `failed` результата, [onTrackDone] вызывается
/// после каждого трека — для живого прогресса в AppBar.
Future<TrackDownloadResult> downloadTracksBatch({
  required List<Media> pending,
  required Future<void> Function(Media track) download,
  required bool Function(int mediaId) isDownloaded,
  required bool Function(int mediaId) isFailed,
  void Function(int downloaded, int failed)? onTrackDone,
  int concurrency = 4,
}) async {
  if (pending.isEmpty) return (downloaded: 0, failed: 0);
  var downloaded = 0;
  var failed = 0;
  final queue = List<Media>.from(pending);

  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final track = queue.removeAt(0);
      try {
        await download(track);
        if (isDownloaded(track.id)) {
          downloaded++;
        } else if (isFailed(track.id)) {
          failed++;
        }
      } catch (_) {
        failed++;
      }
      onTrackDone?.call(downloaded, failed);
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
  return (downloaded: downloaded, failed: failed);
}

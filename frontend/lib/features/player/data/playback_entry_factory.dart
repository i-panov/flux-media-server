import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/core/utils/media_image_url.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Собирает элементы плейлиста для mpv: локальный файл, если трек
/// скачан, иначе URL потока с текущим токеном.
///
/// Выделено из `PlaybackCoordinator`: сборка — чистая функция от
/// (медиа, токен, baseUrl, кеш), а координатор отвечает за порядок
/// загрузки и состояние. Зависимости — через конструктор, никакого
/// Riverpod внутри: токен читается лениво колбэком, чтобы подхватить
/// refresh без пересоздания фабрики.
class PlaybackEntryFactory {
  new({
    required this.baseUrl,
    required this.tokenReader,
    required this.localPathFor,
  });

  final String baseUrl;

  /// Текущий auth-токен (или null). Вызывается на каждую сборку.
  final String? Function() tokenReader;

  /// Локальный путь скачанного трека (или null). Ошибки кеша глотаются
  /// внутри — трек просто пойдёт по сети.
  final Future<String?> Function(int mediaId) localPathFor;

  Future<List<AudioQueueEntry>> buildEntries(List<Media> items) {
    final token = tokenReader();
    return Future.wait(items.map((media) => buildEntry(media, token)));
  }

  Future<AudioQueueEntry> buildEntry(Media media, String? token) async {
    String? localPath;
    try {
      localPath = await localPathFor(media.id);
    } catch (e) {
      AppLogger.warn('Offline cache lookup failed for ${media.id}: $e');
    }
    final isLocal = localPath != null;
    return AudioQueueEntry(
      mediaId: media.id,
      url: localPath ?? '$baseUrl/media/${media.id}/stream',
      title: media.title,
      artist: media.artists.isEmpty
          ? null
          : media.artists.map((a) => a.name).join(', '),
      artUri: coverUrlFor(media, isLocal: isLocal),
      duration: media.duration != null
          ? Duration(seconds: media.duration!)
          : null,
      httpHeaders: (!isLocal && token != null)
          ? <String, String>{'Authorization': 'Bearer $token'}
          : null,
    );
  }

  /// Обложка для MediaItem уведомления; без рисунка — null.
  ///
  /// Уже скачанный трек показывается без обложки: локальный файл
  /// не требует авторизации, а тянуть её заново незачем.
  String? coverUrlFor(Media media, {required bool isLocal}) {
    if (isLocal) return null;
    if (media.coverUrl?.isNotEmpty ?? false) {
      return buildMediaImageUrl(
        baseUrl: baseUrl,
        mediaId: media.id,
        kind: MediaImageKind.cover,
      );
    }
    if (media.thumbnailUrl?.isNotEmpty ?? false) {
      return buildMediaImageUrl(
        baseUrl: baseUrl,
        mediaId: media.id,
        kind: MediaImageKind.thumb,
      );
    }
    return null;
  }
}

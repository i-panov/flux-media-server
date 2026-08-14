import 'package:flux_media_server/shared/models/lyrics.dart';

/// Локальный кеш лирики (офлайн-доступ).
///
/// Абстракция в domain-слое, чтобы presentation-провайдеры не зависели
/// от data-слоя фичи offline напрямую.
abstract class LyricsCacheRepository {
  Future<Lyrics?> getCachedLyrics(int mediaId);
  Future<void> saveLyrics(int mediaId, Lyrics lyrics);
}

import 'package:flutter/foundation.dart';

/// Схема именования файлов и ключей офлайн-кеша.
///
/// Выделено из `OfflineCacheService`: формат `user_{id}_`-неймспейса
/// использовался в десятке методов (имена файлов, ключи метаданных/лирики,
/// ключ текущего пользователя, легаси-ключи миграции), но это чистая
/// функция от (build-флаг, userId) без зависимости от ФС, prefs и сети.
/// Граница:
///
/// - вход — только `userId` (0 = неизвестен, как и было в сервисе);
/// - никаких чтений диска/prefs внутри, только строки;
/// - легаси-ключи (до введения user-префикса) рядом, чтобы миграция
///   не дублировала формат в двух местах.
class CacheNaming {
  const new({required this.userId, bool? debugOverride}) : _debug = debugOverride;

  /// id пользователя-владельца неймспейса (0, если неизвестен).
  final int userId;

  /// Build-флаг для префикса. Параметр вместо прямого `kDebugMode`,
  /// чтобы обе ветки покрывались unit-тестами на одной машине.
  final bool? _debug;

  bool get _isDebug => _debug ?? kDebugMode;

  /// Префикс, разделяющий файлы debug- и release-сборок.
  String get prefix => _isDebug ? 'debug_' : 'release_';

  /// Ключ в prefs с id текущего пользователя (для привязки кеша).
  String get userIdKey => '${prefix}flux_current_user_id';

  /// Префикс файлов любого пользователя (для отсева чужих/легаси при
  /// миграции: мигрируем только файлы без user-неймспейса).
  String get anyUserPrefix => '${prefix}user_';

  /// Префикс файлов текущего пользователя (для листинга директории).
  String get userFilePrefix => '${prefix}user_${userId}_';

  /// Файл скачанного медиа в documents-директории.
  String fileName(int mediaId) => '${prefix}user_${userId}_flux_media_$mediaId';

  /// Ключ метаданных медиа в prefs.
  String metaKey(int mediaId) => '${prefix}user_${userId}_flux_meta_$mediaId';

  /// Ключ лирики в prefs.
  String lyricsKey(int mediaId) =>
      '${prefix}user_${userId}_flux_lyrics_$mediaId';

  /// Флаг завершённой миграции легаси-файлов пользователя.
  String migratedKey(int uid) => '${prefix}flux_migrated_user_$uid';

  /// Легаси-ключ метаданных (до user-префикса) — только для миграции.
  String legacyMetaKey(int mediaId) => '${prefix}flux_meta_$mediaId';

  /// Легаси-ключ лирики (до user-префикса) — только для миграции.
  String legacyLyricsKey(int mediaId) => '${prefix}flux_lyrics_$mediaId';
}

// Намеренно используем асинхронные версии dart:io (exists/delete/rename/
// list/stat): синхронные блокируют UI-изолят — именно это правило и
// устраняло ревью.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Загрузка отменена пользователем через [OfflineCacheService.cancelDownload].
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download cancelled';
}

/// Manages offline media downloads.
/// Files are stored in the app's documents directory, с префиксом
/// `user_{id}_`, чтобы кеши разных пользователей не пересекались.
class OfflineCacheService {
  OfflineCacheService(this._ref, this._baseUrl);

  final Ref _ref;
  final String _baseUrl;

  /// Prefix for file names so debug and release builds don't share
  /// cached files.
  static const String _prefix = kDebugMode ? 'debug_' : 'release_';

  /// Ключ в prefs с id текущего пользователя (для привязки кеша).
  static const String _userIdKey = '${_prefix}flux_current_user_id';

  /// Кэшированный id пользователя (null, пока не определён).
  int? _userId;

  /// Идентификатор активного пользователя или 0, если неизвестен.
  int get _resolvedUserId => _userId ?? 0;

  String _fileName(int mediaId) =>
      '${_prefix}user_${_resolvedUserId}_flux_media_$mediaId';

  String _metaKey(int mediaId) =>
      '${_prefix}user_${_resolvedUserId}_flux_meta_$mediaId';

  String _lyricsKey(int mediaId) =>
      '${_prefix}user_${_resolvedUserId}_flux_lyrics_$mediaId';

  String? get _authToken => _ref.read(settingsProvider).settings.authToken;

  /// Guard against parallel token refresh calls.
  bool _isRefreshing = false;

  /// Track active downloads by mediaId to prevent parallel downloads
  /// of the same file (which would corrupt the .part file).
  final Set<int> _activeDownloads = {};

  /// Загрузки, отменённые пользователем.
  final Set<int> _cancelledDownloads = {};

  /// Guard против рекурсивного вызова [_enforceCacheLimit].
  bool _enforcingLimit = false;

  /// Maximum total cache size: 5 GB.
  static const int _maxCacheBytes = 5 * 1024 * 1024 * 1024;

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  /// Определяет id пользователя (из состояния авторизации или кеша prefs)
  /// и мигрирует легаси-файлы без user-префикса. Вызывается в начале
  /// каждой публичной операции.
  Future<void> _ensureUserId() async {
    if (_userId != null) return;
    final authState = _ref.read(authProvider);
    if (authState is AuthAuthenticated) {
      _userId = authState.user.id;
      await _prefs.setInt(_userIdKey, authState.user.id);
    } else {
      _userId = _prefs.getInt(_userIdKey);
    }
    await _migrateLegacyFiles();
  }

  /// Мигрирует файлы/метаданные, сохранённые до введения user-префикса,
  /// в неймспейс текущего пользователя.
  Future<void> _migrateLegacyFiles() async {
    final uid = _userId;
    if (uid == null) return;
    final migratedKey = '${_prefix}flux_migrated_user_$uid';
    if (_prefs.getBool(migratedKey) ?? false) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final entries = await dir.list().toList();
      final idPattern = RegExp(r'flux_media_(\d+)$');
      for (final e in entries) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        // Файлы с user-префиксом (включая чужие `debug_user_9_*`) не трогаем:
        // мигрируем только файлы без неймспейса пользователя.
        if (name.startsWith('${_prefix}user_')) continue;
        if (!name.startsWith(_prefix)) continue;
        final match = idPattern.firstMatch(name);
        if (match == null) continue;
        final id = int.parse(match.group(1)!);
        final legacy = File(e.path);
        final target = File('${dir.path}/${_fileName(id)}');
        if (legacy.path != target.path) {
          if (await target.exists()) {
            await legacy.delete();
          } else {
            await legacy.rename(target.path);
          }
        }
        // Переносим метаданные и лирику в ключи с user-префиксом.
        final oldMetaKey = '${_prefix}flux_meta_$id';
        final meta = _prefs.getString(oldMetaKey);
        if (meta != null && !_prefs.containsKey(_metaKey(id))) {
          await _prefs.setString(_metaKey(id), meta);
        }
        await _prefs.remove(oldMetaKey);
        final oldLyricsKey = '${_prefix}flux_lyrics_$id';
        final lyrics = _prefs.getString(oldLyricsKey);
        if (lyrics != null && !_prefs.containsKey(_lyricsKey(id))) {
          await _prefs.setString(_lyricsKey(id), lyrics);
        }
        await _prefs.remove(oldLyricsKey);
      }
      await _prefs.setBool(migratedKey, true);
    } catch (e) {
      AppLogger.error('Error migrating legacy cache files', e);
    }
  }

  /// Returns the local file path for a cached media item, or null if
  /// not cached.
  Future<String?> getLocalPath(int mediaId) async {
    try {
      await _ensureUserId();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_fileName(mediaId)}');
      if (await file.exists()) {
        return file.path;
      }
    } catch (e) {
      AppLogger.error('Error checking local path', e);
    }
    return null;
  }

  /// Downloads a media file for offline use with progress reporting.
  /// [onProgress] receives (bytesReceived, totalBytes).
  /// Returns the local file path on success.
  Future<String> download(
    Media media, {
    void Function(int received, int? total)? onProgress,
  }) async {
    await _ensureUserId();
    // Prevent parallel downloads of the same mediaId — two sinks writing
    // to the same .part file would corrupt it.
    if (_activeDownloads.contains(media.id)) {
      throw Exception('Download already in progress for media ${media.id}');
    }
    _activeDownloads.add(media.id);
    _cancelledDownloads.remove(media.id);

    try {
      return await _downloadInternal(media, onProgress: onProgress);
    } finally {
      _activeDownloads.remove(media.id);
      _cancelledDownloads.remove(media.id);
    }
  }

  Future<String> _downloadInternal(
    Media media, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = '$_baseUrl/media/${media.id}/stream';
    var token = _authToken;
    AppLogger.info('Download started: $url, token=${token != null}');

    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.Request('GET', Uri.parse(url));
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final client = http.Client();
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/${_fileName(media.id)}');
      final partFile = File('${localFile.path}.part');

      try {
        final response = await client.send(request).timeout(
              const Duration(minutes: 10),
              onTimeout: () => throw Exception('Download timed out'),
            );
        AppLogger.info('Download response: ${response.statusCode}');

        if (response.statusCode == 401 && attempt == 0) {
          token = await _refreshToken();
          if (token != null) continue;
          throw Exception('Download failed: 401');
        }

        if (response.statusCode != 200) {
          throw Exception('Download failed: ${response.statusCode}');
        }

        final total = response.contentLength;
        final sink = partFile.openWrite();

        var received = 0;
        try {
          await response.stream.map((chunk) {
            if (_cancelledDownloads.contains(media.id)) {
              throw const DownloadCancelledException();
            }
            received += chunk.length;
            onProgress?.call(received, total);
            return chunk;
          }).pipe(sink);
        } finally {
          try {
            await sink.close();
          } on FileSystemException {
            // Поток завершился ошибкой (отмена загрузки): IOSink уже
            // закрыт, повторный close() кидает «File closed» и маскирует
            // исходное исключение (DownloadCancelledException).
          }
        }

        if (await localFile.exists()) {
          await localFile.delete();
        }
        await partFile.rename(localFile.path);

        // Save media metadata for offline access.
        await saveMetadata(media);

        // Проверяем лимит кеша после успешной загрузки.
        await _enforceCacheLimit();

        return localFile.path;
      } catch (e) {
        if (await partFile.exists()) {
          try {
            await partFile.delete();
          } on Exception {
            // Best-effort cleanup of the partial file.
          }
        }
        rethrow;
      } finally {
        client.close();
      }
    }
    throw Exception('Download failed');
  }

  /// Отменяет активную загрузку [mediaId]. Следующая проверка в потоке
  /// прервёт её с [DownloadCancelledException], .part-файл подчистится.
  void cancelDownload(int mediaId) {
    _cancelledDownloads.add(mediaId);
  }

  Future<String?> _refreshToken() async {
    // Guard against parallel refresh calls — two concurrent 401s would
    // each POST /auth/refresh, both succeed, and invalidate each other's
    // tokens (only the last one survives).
    if (_isRefreshing) return null;
    _isRefreshing = true;
    try {
      final refreshToken = _ref.read(settingsProvider).settings.refreshToken;
      // Используем единый refresher: параллельные 401-запросы (включая
      // запросы из интерцептора) ждут один общий refresh.
      final refreshed =
          await _ref.read(authTokenRefresherProvider).refresh(refreshToken);
      if (!refreshed) return null;
      return _ref.read(settingsProvider).settings.authToken;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Saves media metadata to SharedPreferences for offline access.
  Future<void> saveMetadata(Media media) async {
    try {
      await _ensureUserId();
      await _prefs.setString(_metaKey(media.id), jsonEncode(media.toJson()));
    } catch (e) {
      AppLogger.error('Error saving metadata', e);
    }
  }

  /// Saves lyrics to SharedPreferences for offline access.
  Future<void> saveLyrics(int mediaId, Lyrics lyrics) async {
    try {
      await _ensureUserId();
      await _prefs.setString(_lyricsKey(mediaId), jsonEncode(lyrics.toJson()));
    } catch (e) {
      AppLogger.error('Error saving lyrics', e);
    }
  }

  /// Returns locally cached lyrics, or null if not saved.
  Future<Lyrics?> getCachedLyrics(int mediaId) async {
    try {
      await _ensureUserId();
      final jsonStr = _prefs.getString(_lyricsKey(mediaId));
      if (jsonStr == null) return null;
      return Lyrics.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error reading cached lyrics', e);
      return null;
    }
  }

  /// Removes a downloaded media file, its metadata and lyrics.
  /// Also cleans up any incomplete `.part` files.
  Future<void> remove(int mediaId) async {
    try {
      await _ensureUserId();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_fileName(mediaId)}');
      if (await file.exists()) {
        await file.delete();
      }
      // Clean up partial download file.
      final partFile = File('${dir.path}/${_fileName(mediaId)}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }
      await _prefs.remove(_metaKey(mediaId));
      await _prefs.remove(_lyricsKey(mediaId));
      // Enforce cache size limit after removal.
      await _enforceCacheLimit();
    } catch (e) {
      AppLogger.error('Error removing cached file', e);
    }
  }

  /// Returns true if the media item is available offline.
  Future<bool> isCached(int mediaId) async {
    return await getLocalPath(mediaId) != null;
  }

  /// Returns a list of cached media IDs (только текущего пользователя).
  Future<List<int>> getCachedIds() async {
    try {
      await _ensureUserId();
      final dir = await getApplicationDocumentsDirectory();
      final entries = await dir.list().toList();
      final prefix = '${_prefix}user_${_resolvedUserId}_';
      final idPattern = RegExp(r'flux_media_(\d+)$');
      final ids = <int>[];
      for (final e in entries) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        final match = idPattern.firstMatch(name);
        if (match != null) {
          ids.add(int.parse(match.group(1)!));
        }
      }
      return ids;
    } catch (e) {
      AppLogger.error('Error listing cached files', e);
      return [];
    }
  }

  /// Enforces the maximum cache size by removing the oldest downloads.
  Future<void> _enforceCacheLimit() async {
    if (_enforcingLimit) return;
    _enforcingLimit = true;
    try {
      await _ensureUserId();
      final dir = await getApplicationDocumentsDirectory();
      final entries = await dir.list().toList();
      final prefix = '${_prefix}user_${_resolvedUserId}_';
      final idPattern = RegExp(r'flux_media_(\d+)$');
      final fileStats = <(int, int)>[]; // (mediaId, fileSize)

      for (final e in entries) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        final match = idPattern.firstMatch(name);
        if (match != null) {
          final id = int.parse(match.group(1)!);
          try {
            final stat = await e.stat();
            fileStats.add((id, stat.size));
          } on Exception {
            // Best-effort: skip files we can't stat.
          }
        }
      }

      var totalSize =
          fileStats.fold<int>(0, (prev, curr) => prev + curr.$2);

      // Remove oldest downloads (sorted by mediaId as a proxy for age).
      fileStats.sort((a, b) => a.$1.compareTo(b.$1));
      for (final (id, size) in fileStats) {
        if (totalSize <= _maxCacheBytes) break;
        await remove(id);
        totalSize -= size;
      }
    } catch (e) {
      AppLogger.error('Error enforcing cache limit', e);
    } finally {
      _enforcingLimit = false;
    }
  }

  /// Returns cached media items by reading metadata from SharedPreferences.
  /// Works offline — no API calls.
  Future<List<Media>> getCachedMedia() async {
    try {
      final ids = await getCachedIds();
      final mediaList = <Media>[];
      for (final id in ids) {
        final jsonStr = _prefs.getString(_metaKey(id));
        if (jsonStr == null) continue;
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          mediaList.add(Media.fromJson(json));
        } catch (e) {
          AppLogger.error('Error reading cached metadata for media $id', e);
        }
      }
      return mediaList;
    } catch (e) {
      AppLogger.error('Error listing cached media', e);
      return [];
    }
  }

  /// Полная очистка кеша текущего пользователя: файлы, метаданные,
  /// лирика. Вызывается при logout.
  Future<void> clearUserCache() async {
    final uid = _userId;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final entries = await dir.list().toList();
      final idPattern = RegExp(r'flux_media_(\d+)(?:\.part)?$');
      if (uid != null) {
        final prefix = '${_prefix}user_${uid}_';
        for (final e in entries) {
          if (e is! File) continue;
          final name = e.uri.pathSegments.last;
          if (name.startsWith(prefix) && idPattern.hasMatch(name)) {
            await e.delete();
          }
        }
        final migratedKey = '${_prefix}flux_migrated_user_$uid';
        await _prefs.remove(migratedKey);
      }
      // Удаляем метаданные/лирику пользователя из prefs.
      final keyPrefix = '${_prefix}user_${uid ?? 0}_';
      for (final key in _prefs.getKeys().toList()) {
        if (key.startsWith(keyPrefix) &&
            (key.contains('flux_meta_') || key.contains('flux_lyrics_'))) {
          await _prefs.remove(key);
        }
      }
      await _prefs.remove(_userIdKey);
      _userId = null;
      _activeDownloads.clear();
      _cancelledDownloads.clear();
    } catch (e) {
      AppLogger.error('Error clearing user cache', e);
    }
  }
}

/// Provider for the offline cache service.
final offlineCacheServiceProvider = Provider<OfflineCacheService>((ref) {
  return OfflineCacheService(
    ref,
    ref.watch(baseUrlProvider),
  );
});

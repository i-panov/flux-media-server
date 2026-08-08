import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/lyrics/domain/usecases/get_lyrics.dart';
import 'package:flux_media_server/features/lyrics/presentation/providers/lyrics_provider.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Manages offline media downloads.
/// Files are stored in the app's documents directory.
class OfflineCacheService {
  OfflineCacheService(this._ref, this._baseUrl);

  final Ref _ref;
  final String _baseUrl;

  /// Prefix for file names so debug and release builds don't share cached files.
  static final String _prefix = kDebugMode ? 'debug_' : 'release_';

  String _fileName(int mediaId) => '${_prefix}flux_media_$mediaId';
  static String _metaKey(int mediaId) => '${_prefix}flux_meta_$mediaId';
  static String _lyricsKey(int mediaId) => '${_prefix}flux_lyrics_$mediaId';

  String? get _authToken => _ref.read(settingsProvider).settings.authToken;

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  /// Returns the local file path for a cached media item, or null if not cached.
  Future<String?> getLocalPath(int mediaId) async {
    try {
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
        final response = await client.send(request);
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

        int received = 0;
        try {
          await response.stream.map((chunk) {
            received += chunk.length;
            onProgress?.call(received, total);
            return chunk;
          }).pipe(sink);
        } finally {
          await sink.close();
        }

        if (await localFile.exists()) {
          await localFile.delete();
        }
        await partFile.rename(localFile.path);

        // Save media metadata for offline access.
        await saveMetadata(media);

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

  Future<String?> _refreshToken() async {
    final refreshToken = _ref.read(settingsProvider).settings.refreshToken;
    if (refreshToken == null) return null;

    try {
      final baseUrl = _ref.read(baseUrlProvider);
      final uri = Uri.parse('$baseUrl/auth/refresh');
      final httpResponse = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (httpResponse.statusCode == 200) {
        final data = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        final newAccessToken = data['token'] as String;
        final newRefreshToken = data['refresh_token'] as String;
        await _ref
            .read(settingsProvider.notifier)
            .setTokens(newAccessToken, newRefreshToken);
        return newAccessToken;
      }
    } catch (_) {}
    return null;
  }

  /// Saves media metadata to SharedPreferences for offline access.
  Future<void> saveMetadata(Media media) async {
    try {
      await _prefs.setString(_metaKey(media.id), jsonEncode(media.toJson()));
    } catch (e) {
      AppLogger.error('Error saving metadata', e);
    }
  }

  /// Saves lyrics to SharedPreferences for offline access.
  Future<void> saveLyrics(int mediaId, Lyrics lyrics) async {
    try {
      await _prefs.setString(_lyricsKey(mediaId), jsonEncode(lyrics.toJson()));
    } catch (e) {
      AppLogger.error('Error saving lyrics', e);
    }
  }

  /// Returns locally cached lyrics, or null if not saved.
  Lyrics? getCachedLyrics(int mediaId) {
    final jsonStr = _prefs.getString(_lyricsKey(mediaId));
    if (jsonStr == null) return null;
    try {
      return Lyrics.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error reading cached lyrics', e);
      return null;
    }
  }

  /// Removes a downloaded media file, its metadata and lyrics.
  Future<void> remove(int mediaId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_fileName(mediaId)}');
      if (await file.exists()) {
        await file.delete();
      }
      await _prefs.remove(_metaKey(mediaId));
      await _prefs.remove(_lyricsKey(mediaId));
    } catch (e) {
      AppLogger.error('Error removing cached file', e);
    }
  }

  /// Returns true if the media item is available offline.
  Future<bool> isCached(int mediaId) async {
    return await getLocalPath(mediaId) != null;
  }

  /// Returns a list of cached media IDs.
  Future<List<int>> getCachedIds() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync();
      final pattern = RegExp(r'flux_media_(\d+)');
      final ids = <int>[];
      for (final f in files) {
        final match = pattern.firstMatch(f.path);
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
}

/// Provider for the offline cache service.
final offlineCacheServiceProvider = Provider<OfflineCacheService>((ref) {
  return OfflineCacheService(
    ref,
    ref.watch(baseUrlProvider),
  );
});

/// State notifier for managing download state of a specific media item.
class DownloadNotifier extends FamilyNotifier<DownloadState, int> {
  @override
  DownloadState build(int arg) {
    checkStatus(arg);
    return const DownloadState.idle();
  }

  OfflineCacheService get _cacheService =>
      ref.read(offlineCacheServiceProvider);

  /// Checks if the media item is already downloaded.
  Future<void> checkStatus(int mediaId) async {
    final cached = await _cacheService.isCached(mediaId);
    if (state is! DownloadDownloading) {
      state = cached ? const DownloadState.downloaded() : const DownloadState.idle();
    }
  }

  /// Starts downloading the media item with progress tracking.
  Future<void> download(Media media) async {
    state = const DownloadState.downloading(progress: 0.0);
    try {
      await _cacheService.download(
        media,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            final progress = received / total;
            state = DownloadState.downloading(progress: progress);
          }
        },
      );
      state = const DownloadState.downloaded();

      // Try to fetch and cache lyrics for offline access.
      try {
        final getLyrics = ref.read(getLyricsProvider);
        final result = await getLyrics(media.id);
        result.fold(
          (_) => null,
          (lyrics) {
            if (lyrics != null) {
              _cacheService.saveLyrics(media.id, lyrics);
            }
          },
        );
      } catch (_) {}

      ref.read(downloadsInvalidatorProvider.notifier).state++;
    } catch (e, st) {
      AppLogger.error('Download failed', e, st);
      state = DownloadState.error(e.toString());
    }
  }

  /// Removes the downloaded file.
  Future<void> remove(int mediaId) async {
    await _cacheService.remove(mediaId);
    state = const DownloadState.idle();
    ref.read(downloadsInvalidatorProvider.notifier).state++;
  }
}

/// Represents the download state of a media item.
sealed class DownloadState {
  const DownloadState();
  const factory DownloadState.idle() = DownloadIdle;
  const factory DownloadState.downloading({double progress}) = DownloadDownloading;
  const factory DownloadState.downloaded() = DownloadDownloaded;
  const factory DownloadState.error(String message) = DownloadError;
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class DownloadDownloading extends DownloadState {
  const DownloadDownloading({this.progress = 0.0});
  final double progress;
}

class DownloadDownloaded extends DownloadState {
  const DownloadDownloaded();
}

class DownloadError extends DownloadState {
  const DownloadError(this.message);
  final String message;
}

/// Provider for download state of a specific media item.
/// Not auto-disposed: downloads must survive widget rebuilds/navigation.
final downloadNotifierProvider =
    NotifierProvider.family<DownloadNotifier, DownloadState, int>(
  DownloadNotifier.new,
);

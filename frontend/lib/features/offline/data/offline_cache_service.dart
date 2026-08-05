import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
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

  String? get _authToken => _ref.read(settingsProvider).settings.authToken;

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

  /// Removes a downloaded media file.
  Future<void> remove(int mediaId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_fileName(mediaId)}');
      if (await file.exists()) {
        await file.delete();
      }
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
      final pattern = RegExp('${_prefix}flux_media_(\d+)');
      return files
          .map((f) {
            final match = pattern.firstMatch(f.path);
            return match != null ? int.parse(match.group(1)!) : null;
          })
          .whereType<int>()
          .toList();
    } catch (e) {
      AppLogger.error('Error listing cached files', e);
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
      ref.invalidate(downloadsProvider);
    } catch (e, st) {
      AppLogger.error('Download failed', e, st);
      state = DownloadState.error(e.toString());
    }
  }

  /// Removes the downloaded file.
  Future<void> remove(int mediaId) async {
    await _cacheService.remove(mediaId);
    state = const DownloadState.idle();
    ref.invalidate(downloadsProvider);
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

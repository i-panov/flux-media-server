import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Manages offline media downloads.
/// Files are stored in the app's documents directory.
class OfflineCacheService {
  OfflineCacheService(this._baseUrl, this._authToken);

  final String _baseUrl;
  final String? _authToken;

  /// Returns the local file path for a cached media item, or null if not cached.
  Future<String?> getLocalPath(int mediaId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/flux_media_$mediaId');
      if (await file.exists()) {
        return file.path;
      }
    } catch (e) {
      debugPrint('Error checking local path: $e');
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
    final request = http.Request('GET', Uri.parse(url));
    if (_authToken != null) {
      request.headers['Authorization'] = 'Bearer $_authToken';
    }

    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    final total = response.contentLength;
    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/flux_media_${media.id}');
    final sink = localFile.openWrite();

    int received = 0;
    await response.stream.map((chunk) {
      received += chunk.length;
      onProgress?.call(received, total);
      return chunk;
    }).pipe(sink);

    return localFile.path;
  }

  /// Removes a downloaded media file.
  Future<void> remove(int mediaId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/flux_media_$mediaId');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error removing cached file: $e');
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
      return files
          .where((f) => f.path.contains('flux_media_'))
          .map((f) {
            final match = RegExp(r'flux_media_(\d+)').firstMatch(f.path);
            return match != null ? int.parse(match.group(1)!) : null;
          })
          .whereType<int>()
          .toList();
    } catch (e) {
      debugPrint('Error listing cached files: $e');
      return [];
    }
  }
}

/// Provider for the offline cache service.
final offlineCacheServiceProvider = Provider<OfflineCacheService>((ref) {
  return OfflineCacheService(ref.watch(baseUrlProvider), null);
});

/// State notifier for managing download state of a specific media item.
class DownloadNotifier extends StateNotifier<DownloadState> {
  DownloadNotifier(this._cacheService) : super(const DownloadState.idle());

  final OfflineCacheService _cacheService;

  /// Checks if the media item is already downloaded.
  Future<void> checkStatus(int mediaId) async {
    final cached = await _cacheService.isCached(mediaId);
    state = cached ? const DownloadState.downloaded() : const DownloadState.idle();
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
    } catch (e) {
      state = DownloadState.error(e.toString());
    }
  }

  /// Removes the downloaded file.
  Future<void> remove(int mediaId) async {
    await _cacheService.remove(mediaId);
    state = const DownloadState.idle();
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
final downloadNotifierProvider =
    StateNotifierProvider.autoDispose.family<DownloadNotifier, DownloadState, int>(
  (ref, mediaId) {
    final notifier = DownloadNotifier(ref.watch(offlineCacheServiceProvider));
    notifier.checkStatus(mediaId);
    return notifier;
  },
);

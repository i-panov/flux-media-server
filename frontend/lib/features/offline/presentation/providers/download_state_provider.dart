import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/lyrics/presentation/providers/lyrics_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Represents the download state of a media item.
sealed class DownloadState {
  const DownloadState();
  const factory DownloadState.idle() = DownloadIdle;
  const factory DownloadState.downloading({double progress}) =
      DownloadDownloading;
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
      state = cached
          ? const DownloadState.downloaded()
          : const DownloadState.idle();
    }
  }

  /// Starts downloading the media item with progress tracking.
  Future<void> download(Media media) async {
    state = const DownloadState.downloading();
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
    } on DownloadCancelledException {
      state = const DownloadState.idle();
    } catch (e, st) {
      AppLogger.error('Download failed', e, st);
      state = DownloadState.error(e.toString());
    }
  }

  /// Отменяет активную загрузку.
  Future<void> cancel(int mediaId) async {
    _cacheService.cancelDownload(mediaId);
    state = const DownloadState.idle();
  }

  /// Removes the downloaded file.
  Future<void> remove(int mediaId) async {
    await _cacheService.remove(mediaId);
    state = const DownloadState.idle();
    ref.read(downloadsInvalidatorProvider.notifier).state++;
  }
}

/// Provider for download state of a specific media item.
/// Not auto-disposed: downloads must survive widget rebuilds/navigation.
final downloadNotifierProvider =
    NotifierProvider.family<DownloadNotifier, DownloadState, int>(
  DownloadNotifier.new,
);

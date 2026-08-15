import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
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

  /// Время последнего обновления прогресса (троттлинг rebuild-ов).
  DateTime? _lastProgressUpdate;

  /// Checks if the media item is already downloaded.
  Future<void> checkStatus(int mediaId) async {
    final cached = await _cacheService.isCached(mediaId);
    // Применяем результат только из idle: гонка с download (результат
    // isCached, полученный до завершения загрузки) не откатывает
    // состояние downloaded/error/downloading.
    if (state is! DownloadIdle) return;
    state = cached
        ? const DownloadState.downloaded()
        : const DownloadState.idle();
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
            // Троттлинг ~100 мс: иначе каждый чанк делает rebuild.
            final now = DateTime.now();
            if (_lastProgressUpdate == null ||
                now.difference(_lastProgressUpdate!) >=
                    const Duration(milliseconds: 100)) {
              _lastProgressUpdate = now;
              state = DownloadState.downloading(progress: progress);
            }
          }
        },
      );
      state = const DownloadState.downloaded();

      ref.read(downloadsInvalidatorProvider.notifier).state++;
    } on DownloadCancelledException {
      state = const DownloadState.idle();
    } on FileSystemException catch (e) {
      // Маппим нехватку места на диске в человекочитаемое сообщение.
      final noSpace = e.osError?.errorCode == 28 ||
          e.message.toLowerCase().contains('no space');
      state = DownloadError(
        noSpace
            ? 'Not enough storage space. Free up space and try again.'
            : e.message,
      );
    } catch (e, st) {
      AppLogger.error('Download failed', e, st);
      state = DownloadError(e.toString());
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

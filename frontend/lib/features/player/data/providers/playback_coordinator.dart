import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/datasources/audio_player_datasource.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_coordinator.freezed.dart';

@freezed
class PlaybackState with _$PlaybackState {
  const factory PlaybackState.initial() = PlaybackInitial;
  const factory PlaybackState.playing({
    required Media media,
    required String type, // 'audio' or 'video'
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
    @Default(1.0) double speed,
    Duration? savedPosition,
  }) = PlaybackPlaying;
  const factory PlaybackState.completed() = PlaybackCompleted;
  const factory PlaybackState.loading() = PlaybackLoading;
  const factory PlaybackState.error({required String message}) = PlaybackError;
}

/// Manages unified playback across audio and video.
/// Handles mutual exclusion: starting video stops audio and vice versa.
class PlaybackCoordinator extends StateNotifier<PlaybackState>
    implements PlaybackController {
  PlaybackCoordinator(
    this._audioPlayer,
    this._baseUrl,
    this._ref,
  ) : super(const PlaybackState.initial());

  final AudioPlayerDatasource _audioPlayer;
  final String _baseUrl;

  /// Used to lazily read the current auth token (so token refreshes don't
  /// reset the playback state) and to coordinate with the video player.
  final Ref _ref;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;
  bool _isPlaying = false;

  /// Lazily reads the video player datasource. Using ref.read instead of
  /// ref.watch prevents this long-lived provider from keeping the
  /// autoDispose videoPlayerDatasourceProvider alive.
  VideoPlayerDatasource get _videoPlayer =>
      _ref.read(videoPlayerDatasourceProvider);

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _cancelProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _cancelProgressTimer();
    super.dispose();
  }

  /// Starts playback of [media]. Stops any current playback first.
  /// Serializes concurrent play() calls to prevent race conditions.
  Future<void> play(Media media) async {
    // Serialize: reject concurrent play() calls to prevent interleaving
    // of async load/play/seek operations on different player instances.
    if (_isPlaying) return;
    _isPlaying = true;

    state = const PlaybackState.loading();

    try {
      await _playInternal(media);
    } catch (e) {
      state = PlaybackState.error(message: e.toString());
    } finally {
      _isPlaying = false;
    }
  }

  Future<void> _playInternal(Media media) async {
    // Save progress of the current playback before switching.
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }

    _cancelSubscriptions();
    _cancelProgressTimer();

    // Use local file if downloaded, otherwise stream from server.
    final cacheService = _ref.read(offlineCacheServiceProvider);
    final localPath = await cacheService.getLocalPath(media.id);
    final url = localPath ?? '$_baseUrl/media/${media.id}/stream';
    final token = _ref.read(settingsProvider).settings.authToken;
    final headers = localPath == null && token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : null;

    if (media.type == MediaType.audio) {
      // Mutual exclusion: stop video playback before starting audio.
      await _videoPlayer.stop();

      // Build cover art URL for system notification.
      // Skip when offline — no server to fetch from.
      String? coverUrl;
      if (localPath == null) {
        coverUrl = (media.coverUrl != null && media.coverUrl!.isNotEmpty)
            ? '$_baseUrl/media/${media.id}/cover'
            : (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty
                ? '$_baseUrl/media/${media.id}/thumb'
                : null);
      }

      // Start audio playback with metadata for the system notification.
      await _audioPlayer.loadSource(
        url: url,
        title: media.title,
        artist: media.artists.map((a) => a.name).join(', '),
        artUri: coverUrl,
        duration:
            media.duration != null ? Duration(seconds: media.duration!) : null,
        httpHeaders: headers,
      );
      await _audioPlayer.play();

      state = PlaybackState.playing(
        media: media,
        type: 'audio',
      );

      _subscribeToStream(_audioPlayer.positionStream, (pos) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(position: pos);
        }
      });
      _subscribeToStream(_audioPlayer.durationStream, (dur) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(duration: dur);
        }
      });
      _subscribeToStream(_audioPlayer.playingStream, (playing) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(isPaused: !playing);
        }
      });
      _subscribeToStream(_audioPlayer.completedStream, _onCompleted);
      _subscribeToStream(_audioPlayer.errorStream, _onPlayerError);
      _subscribeToStream(_audioPlayer.bufferingStream, _onBuffering);
    } else {
      // Mutual exclusion: stop audio playback before starting video.
      await _audioPlayer.stop();

      // Start video playback
      await _videoPlayer.open(url, httpHeaders: headers);
      await _videoPlayer.play();

      // Load saved position for resume dialog (video only).
      final resumePosition = await _loadSavedPosition(media.id);

      state = PlaybackState.playing(
        media: media,
        type: 'video',
        savedPosition: resumePosition != null &&
                resumePosition > const Duration(seconds: 5)
            ? resumePosition
            : null,
      );

      if (resumePosition != null &&
          resumePosition <= const Duration(seconds: 5)) {
        await _videoPlayer.seek(resumePosition);
      }

      _subscribeToStream(_videoPlayer.positionStream, (pos) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(position: pos);
        }
      });
      _subscribeToStream(_videoPlayer.durationStream, (dur) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(duration: dur);
        }
      });
      _subscribeToStream(_videoPlayer.playingStream, (playing) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(isPaused: !playing);
        }
      });
      _subscribeToStream(_videoPlayer.completedStream, _onCompleted);
      _subscribeToStream(_videoPlayer.errorStream, _onPlayerError);
      _subscribeToStream(_videoPlayer.bufferingStream, _onBuffering);
    }

    _startProgressTimer();
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    final current = state;
    if (current is PlaybackPlaying) {
      unawaited(
        _saveProgress(
          current.media.id,
          current.duration ?? current.position,
          current.duration ?? Duration.zero,
          completed: true,
        ),
      );
    }
    _cancelProgressTimer();

    // Don't auto-advance if we're in loading state (user switched tracks).
    if (state is PlaybackLoading) return;

    // Auto-advance to next track in queue if available.
    final queue = _ref.read(playQueueProvider);
    if (queue.hasNext) {
      unawaited(_ref.read(playQueueProvider.notifier).next());
    } else {
      state = const PlaybackState.completed();
    }
  }

  /// Handles player errors (e.g. 401, unreachable stream).
  void _onPlayerError(String error) {
    if (state is PlaybackPlaying || state is PlaybackLoading) {
      state = PlaybackState.error(message: error);
    }
  }

  /// Handles buffering state changes.
  void _onBuffering(bool buffering) {
    // media_kit emits buffering events frequently; we don't want to
    // change state on every tick. The UI can subscribe to the stream
    // directly if it needs a buffering indicator.
  }

  void _subscribeToStream<T>(Stream<T> stream, void Function(T) onNext) {
    final sub = stream.listen(onNext);
    _subscriptions.add(sub);
  }

  /// Returns the saved watch position for [mediaId], or null if there is
  /// none (or the media was already completed).
  Future<Duration?> _loadSavedPosition(int mediaId) async {
    final result = await _ref.read(mediaRepositoryProvider).getProgress();
    return result.fold(
      (_) => null,
      (progressList) {
        for (final p in progressList) {
          if (p.mediaId == mediaId && p.position > 0) {
            return Duration(seconds: p.position);
          }
        }
        return null;
      },
    );
  }

  /// Saves watch progress to the backend. Best-effort: errors are logged
  /// and ignored.
  Future<void> _saveProgress(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) async {
    if (position <= Duration.zero) return;
    try {
      await _ref.read(mediaRepositoryProvider).updateProgress(
            mediaId,
            position: position.inSeconds,
          );
    } on Exception catch (e) {
      developer.log('Failed to save progress: $e');
    }
  }

  /// Periodically persists watch progress while playing.
  void _startProgressTimer() {
    _cancelProgressTimer();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final current = state;
      if (current is PlaybackPlaying && !current.isPaused) {
        unawaited(
          _saveProgress(
            current.media.id,
            current.position,
            current.duration ?? Duration.zero,
          ),
        );
      }
    });
  }

  Future<void> pause() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.pause();
      } else {
        await _videoPlayer.pause();
      }
      state = current.copyWith(isPaused: true);
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }
  }

  Future<void> resume() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.play();
      } else {
        await _videoPlayer.play();
      }
      state = current.copyWith(isPaused: false);
    }
  }

  Future<void> seek(Duration position) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.seek(position);
      } else {
        await _videoPlayer.seek(position);
      }
    }
  }

  /// Sets playback speed (video only).
  Future<void> setSpeed(double speed) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.video) {
        await _videoPlayer.player.setRate(speed);
        state = current.copyWith(speed: speed);
      }
    }
  }

  /// Seeks to the saved position (from the resume dialog).
  Future<void> seekToSavedPosition() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      final saved = current.savedPosition;
      if (saved != null) {
        await _videoPlayer.seek(saved);
        state = current.copyWith(savedPosition: null);
      }
    }
  }

  /// Starts playback from the beginning (from the resume dialog).
  Future<void> startFromBeginning() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _videoPlayer.seek(Duration.zero);
      state = current.copyWith(savedPosition: null);
    }
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  Future<void> stop() async {
    _cancelSubscriptions();
    _cancelProgressTimer();
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.stop();
      } else {
        await _videoPlayer.stop();
      }
    }
    state = const PlaybackState.initial();
  }

  Future<void> reset() async {
    await stop();
  }
}

/// Provider for the audio handler (initialized in main.dart via
/// AudioService.init).
final audioHandlerProvider = Provider<FluxAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in main()');
});

/// Provider for audio player datasource.
final audioPlayerDatasourceProvider = Provider<AudioPlayerDatasource>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final ds = AudioPlayerDatasource(handler);
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for video player datasource.
/// NOT autoDispose: the PlaybackCoordinator holds it via ref.read across
/// multiple await points. If it were autoDispose, the player could be
/// disposed and recreated between open() and play(), causing operations
/// on different player instances.
final videoPlayerDatasourceProvider = Provider<VideoPlayerDatasource>((ref) {
  final ds = VideoPlayerDatasource();
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for playback coordinator.
final playbackCoordinatorProvider =
    StateNotifierProvider<PlaybackCoordinator, PlaybackState>((ref) {
  return PlaybackCoordinator(
    ref.watch(audioPlayerDatasourceProvider),
    ref.watch(baseUrlProvider),
    ref,
  );
});

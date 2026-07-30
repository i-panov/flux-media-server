import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/player/data/datasources/audio_player_datasource.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
import 'package:flux_media_server/features/player/presentation/providers/player_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

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
  }) = PlaybackPlaying;
  const factory PlaybackState.completed() = PlaybackCompleted;
}

/// Manages unified playback across audio and video.
/// Handles mutual exclusion: starting video stops audio and vice versa.
class PlaybackCoordinator extends StateNotifier<PlaybackState> {
  PlaybackCoordinator(
    this._audioPlayer,
    this._videoPlayer,
    this._baseUrl,
    this._ref,
  ) : super(const PlaybackState.initial());

  final AudioPlayerDatasource _audioPlayer;
  final VideoPlayerDatasource _videoPlayer;
  final String _baseUrl;

  /// Used to lazily read the current auth token (so token refreshes don't
  /// reset the playback state) and to coordinate with the video player.
  final Ref _ref;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;

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
  Future<void> play(Media media) async {
    // Save progress of the current playback before switching.
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _saveProgress(current.media.id, current.position,
          current.duration ?? Duration.zero);
    }

    _cancelSubscriptions();
    _cancelProgressTimer();

    final url = '$_baseUrl/media/${media.id}/stream';
    final token = _ref.read(settingsProvider).settings.authToken;
    final headers = token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : null;

    if (media.type == 'audio') {
      // Mutual exclusion: stop video playback before starting audio.
      await _ref.read(playerProvider.notifier).stop();
      await _videoPlayer.stop();

      // Start audio playback
      await _audioPlayer.open(url, httpHeaders: headers);
      await _audioPlayer.play();

      state = PlaybackState.playing(
        media: media,
        type: 'audio',
        isPaused: false,
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
    } else {
      // Mutual exclusion: stop audio playback before starting video.
      await _audioPlayer.stop();

      // Start video playback
      await _videoPlayer.open(url, httpHeaders: headers);
      await _videoPlayer.play();

      state = PlaybackState.playing(
        media: media,
        type: 'video',
        isPaused: false,
      );

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
    }

    _startProgressTimer();
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    final current = state;
    if (current is PlaybackPlaying) {
      unawaited(_saveProgress(
        current.media.id,
        current.duration ?? current.position,
        current.duration ?? Duration.zero,
        completed: true,
      ));
    }
    _cancelProgressTimer();
    state = const PlaybackState.completed();
  }

  void _subscribeToStream<T>(Stream<T> stream, void Function(T) onNext) {
    final sub = stream.listen(onNext);
    _subscriptions.add(sub);
  }

  /// Saves watch progress to the backend. Best-effort: errors are logged
  /// and ignored.
  Future<void> _saveProgress(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) async {
    if (position <= Duration.zero && completed != true) return;
    try {
      final isCompleted = completed ??
          (duration.inSeconds > 0 &&
              position.inSeconds >= duration.inSeconds * 0.9);
      await _ref.read(mediaRepositoryProvider).updateProgress(
            mediaId,
            position: position.inSeconds,
            duration: duration.inSeconds,
            completed: isCompleted,
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
        unawaited(_saveProgress(
          current.media.id,
          current.position,
          current.duration ?? Duration.zero,
        ));
      }
    });
  }

  Future<void> pause() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == 'audio') {
        await _audioPlayer.pause();
      } else {
        await _videoPlayer.pause();
      }
      if (!mounted) return;
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
      if (current.media.type == 'audio') {
        await _audioPlayer.play();
      } else {
        await _videoPlayer.play();
      }
      if (!mounted) return;
      state = current.copyWith(isPaused: false);
    }
  }

  Future<void> seek(Duration position) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == 'audio') {
        await _audioPlayer.seek(position);
      } else {
        await _videoPlayer.seek(position);
      }
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
      if (current.media.type == 'audio') {
        await _audioPlayer.stop();
      } else {
        await _videoPlayer.stop();
      }
    }
    if (!mounted) return;
    state = const PlaybackState.initial();
  }

  Future<void> reset() async {
    await stop();
  }
}

/// Provider for audio player datasource.
final audioPlayerDatasourceProvider = Provider<AudioPlayerDatasource>((ref) {
  final ds = AudioPlayerDatasource();
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for playback coordinator.
final playbackCoordinatorProvider =
    StateNotifierProvider<PlaybackCoordinator, PlaybackState>((ref) {
  return PlaybackCoordinator(
    ref.watch(audioPlayerDatasourceProvider),
    ref.watch(videoPlayerDatasourceProvider),
    ref.watch(baseUrlProvider),
    ref,
  );
});

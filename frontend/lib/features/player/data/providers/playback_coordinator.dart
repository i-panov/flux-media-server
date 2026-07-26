import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/player/data/datasources/audio_player_datasource.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
import 'package:flux_media_server/features/player/presentation/providers/player_provider.dart';
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
  ) : super(const PlaybackState.initial());

  final AudioPlayerDatasource _audioPlayer;
  final VideoPlayerDatasource _videoPlayer;
  final String _baseUrl;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  /// Starts playback of [media]. Stops any current playback first.
  Future<void> play(Media media) async {
    // Stop current playback and save progress
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      // Save progress to backend
      _saveProgress(current.media.id, current.position, current.duration ?? Duration.zero);
    }

    _cancelSubscriptions();

    final url = '$_baseUrl/media/${media.id}/stream';

    if (media.type == 'audio') {
      // Start audio playback
      await _audioPlayer.open(url);
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
    } else {
      // Start video playback
      await _videoPlayer.open(url);
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
    }
  }

  void _subscribeToStream<T>(Stream<T> stream, void Function(T) onNext) {
    final sub = stream.listen(onNext);
    _subscriptions.add(sub);
  }

  Future<void> _saveProgress(int mediaId, Duration position, Duration duration) async {
    // Save progress silently in background
    // In a real app, we'd use a repository here
    developer.log('Saving progress: media=$mediaId, pos=${position.inSeconds}s, dur=${duration.inSeconds}s');
  }

  Future<void> pause() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == 'audio') {
        await _audioPlayer.pause();
      } else {
        await _videoPlayer.pause();
      }
      state = (state as PlaybackPlaying).copyWith(isPaused: true);
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
      state = (state as PlaybackPlaying).copyWith(isPaused: false);
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

  Future<void> stop() async {
    _cancelSubscriptions();
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == 'audio') {
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
  );
});

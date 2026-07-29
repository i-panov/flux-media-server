import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

part 'player_provider.freezed.dart';

@freezed
class PlayerNotifierState with _$PlayerNotifierState {
  const factory PlayerNotifierState.initial() = PlayerNotifierInitial;
  const factory PlayerNotifierState.playing({
    required Media media,
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
  }) = PlayerNotifierPlaying;
  const factory PlayerNotifierState.completed() = PlayerNotifierCompleted;
  const factory PlayerNotifierState.error({required String message}) =
      PlayerNotifierError;
}

/// Notifier controlling video playback state.
class PlayerNotifier extends StateNotifier<PlayerNotifierState> {
  /// Creates a [PlayerNotifier] with the given [datasource], [baseUrl] and
  /// [ref]. The ref is used to lazily read the current auth token (so token
  /// refreshes don't reset the player state) and to coordinate playback
  /// with the audio player.
  PlayerNotifier(this._datasource, this._baseUrl, this._ref)
      : super(const PlayerNotifierState.initial());

  final VideoPlayerDatasource _datasource;
  final String _baseUrl;
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

  /// Starts playback of [media].
  Future<void> play(Media media) async {
    _cancelSubscriptions();
    _cancelProgressTimer();
    // Mutual exclusion: stop audio playback (mini player / queue) first.
    await _ref.read(playbackCoordinatorProvider.notifier).stop();
    await _ref.read(audioPlayerDatasourceProvider).stop();
    state = PlayerNotifierState.playing(media: media, isPaused: true);
    try {
      final streamUrl = '$_baseUrl/media/${media.id}/stream';
      final token = _ref.read(settingsProvider).settings.authToken;
      final headers = token != null
          ? <String, String>{'Authorization': 'Bearer $token'}
          : null;
      await _datasource.open(streamUrl, httpHeaders: headers);
      // Auto-resume from the saved position, if any.
      final resumePosition = await _loadSavedPosition(media.id);
      await _datasource.play();
      if (resumePosition != null && resumePosition > Duration.zero) {
        await _datasource.seek(resumePosition);
      }
      if (state is PlayerNotifierPlaying) {
        state = (state as PlayerNotifierPlaying).copyWith(isPaused: false);
      }
      _startProgressTimer();

      _subscriptions.add(_datasource.positionStream.listen((position) {
        if (state is PlayerNotifierPlaying) {
          state = (state as PlayerNotifierPlaying).copyWith(position: position);
        }
      }));

      _subscriptions.add(_datasource.durationStream.listen((duration) {
        if (state is PlayerNotifierPlaying) {
          state = (state as PlayerNotifierPlaying).copyWith(duration: duration);
        }
      }));

      _subscriptions.add(_datasource.completedStream.listen((completed) {
        if (completed) {
          complete();
        }
      }));
    } on Exception catch (e) {
      state = PlayerNotifierState.error(message: e.toString());
    }
  }

  /// Returns the saved watch position for [mediaId], or null if there is
  /// none (or the media was already completed).
  Future<Duration?> _loadSavedPosition(int mediaId) async {
    try {
      final result = await _ref.read(mediaRepositoryProvider).getProgress();
      return result.fold(
        (_) => null,
        (progressList) {
          for (final p in progressList) {
            if (p.mediaId == mediaId && !p.completed && p.position > 0) {
              return Duration(seconds: p.position);
            }
          }
          return null;
        },
      );
    } on Exception {
      return null;
    }
  }

  /// Saves watch progress to the backend. Best-effort: errors are ignored.
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
    } on Exception {
      // Progress saving is best-effort.
    }
  }

  /// Periodically persists watch progress while playing.
  void _startProgressTimer() {
    _cancelProgressTimer();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final current = state;
      if (current is PlayerNotifierPlaying && !current.isPaused) {
        unawaited(_saveProgress(
          current.media.id,
          current.position,
          current.duration ?? Duration.zero,
        ));
      }
    });
  }

  /// Pauses the current playback.
  Future<void> pause() async {
    final current = state;
    if (current is PlayerNotifierPlaying) {
      await _datasource.pause();
      if (!mounted) return;
      state = current.copyWith(isPaused: true);
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }
  }

  /// Resumes the current playback.
  Future<void> resume() async {
    if (state is PlayerNotifierPlaying) {
      await _datasource.play();
      if (!mounted) return;
      state = (state as PlayerNotifierPlaying).copyWith(isPaused: false);
    }
  }

  /// Seeks to the given [position].
  Future<void> seek(Duration position) async => _datasource.seek(position);

  /// Updates the duration of the current media.
  void updateDuration(Duration duration) {
    if (state is PlayerNotifierPlaying) {
      state = (state as PlayerNotifierPlaying).copyWith(duration: duration);
    }
  }

  /// Marks playback as completed.
  void complete() {
    final current = state;
    if (current is PlayerNotifierPlaying) {
      unawaited(_saveProgress(
        current.media.id,
        current.duration ?? current.position,
        current.duration ?? Duration.zero,
        completed: true,
      ));
    }
    state = const PlayerNotifierState.completed();
  }

  /// Stops playback and resets to initial state.
  Future<void> stop() async {
    final current = state;
    _cancelSubscriptions();
    _cancelProgressTimer();
    if (current is PlayerNotifierPlaying) {
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }
    await _datasource.stop();
    if (!mounted) return;
    state = const PlayerNotifierState.initial();
  }

  /// Resets the player to initial state.
  Future<void> reset() async {
    await stop();
  }
}

final videoPlayerDatasourceProvider = Provider<VideoPlayerDatasource>((ref) {
  final ds = VideoPlayerDatasource();
  ref.onDispose(ds.dispose);
  return ds;
});

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerNotifierState>((ref) {
  return PlayerNotifier(
    ref.watch(videoPlayerDatasourceProvider),
    ref.watch(baseUrlProvider),
    ref,
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
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

class PlayerNotifier extends StateNotifier<PlayerNotifierState> {
  PlayerNotifier(this._datasource, this._baseUrl)
      : super(const PlayerNotifierState.initial());

  final VideoPlayerDatasource _datasource;
  final String _baseUrl;

  Future<void> play(Media media) async {
    state = PlayerNotifierState.playing(media: media, isPaused: true);
    try {
      await _datasource.open(
        '$_baseUrl/media/${media.id}/stream',
      );
      await _datasource.play();
      state = state.copyWith(isPaused: false);

      _datasource.positionStream.listen((position) {
        if (state is PlayerNotifierPlaying) {
          state = (state as PlayerNotifierPlaying).copyWith(position: position);
        }
      });

      _datasource.durationStream.listen((duration) {
        if (state is PlayerNotifierPlaying && duration != null) {
          state = (state as PlayerNotifierPlaying).copyWith(duration: duration);
        }
      });

      _datasource.playerStateStream.listen((playerState) {
        if (playerState.completed) {
          complete();
        }
      });
    } catch (e) {
      state = PlayerNotifierState.error(message: e.toString());
    }
  }

  Future<void> pause() async {
    if (state is PlayerNotifierPlaying) {
      await _datasource.pause();
      state = (state as PlayerNotifierPlaying).copyWith(isPaused: true);
    }
  }

  Future<void> resume() async {
    if (state is PlayerNotifierPlaying) {
      await _datasource.play();
      state = (state as PlayerNotifierPlaying).copyWith(isPaused: false);
    }
  }

  Future<void> seek(Duration position) async {
    await _datasource.seek(position);
  }

  void updateDuration(Duration duration) {
    if (state is PlayerNotifierPlaying) {
      state = (state as PlayerNotifierPlaying).copyWith(duration: duration);
    }
  }

  void complete() {
    state = const PlayerNotifierState.completed();
  }

  void reset() {
    state = const PlayerNotifierState.initial();
  }
}

final videoPlayerDatasourceProvider = Provider<VideoPlayerDatasource>((ref) {
  final ds = VideoPlayerDatasource();
  ref.onDispose(() => ds.dispose());
  return ds;
});

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerNotifierState>((ref) {
  return PlayerNotifier(
    ref.watch(videoPlayerDatasourceProvider),
    ref.watch(baseUrlProvider),
  );
});

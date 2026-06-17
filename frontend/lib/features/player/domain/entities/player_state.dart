import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/shared/models/media.dart';

part 'player_state.freezed.dart';

@freezed
class PlayerState with _$PlayerState {
  const factory PlayerState.initial() = PlayerInitial;
  const factory PlayerState.playing({
    required Media media,
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
  }) = PlayerPlaying;
  const factory PlayerState.completed() = PlayerCompleted;
  const factory PlayerState.error({required String message}) = PlayerError;
}

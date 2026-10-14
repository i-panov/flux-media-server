import 'package:flux_media_server/shared/models/media.dart';
// MediaType — явно, а не транзитивно через media.dart: общий тип
// состояния не должен зависеть от реэкспорта модели.
// ignore: unnecessary_import
import 'package:flux_media_server/shared/models/media_type.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_state.freezed.dart';

/// Состояние воспроизведения: единое для аудио и видео.
///
/// Живёт отдельно от координатора, чтобы audio-хендлер (уведомление)
/// мог его читать без циклического импорта: coordinator → handler
/// уже существует, обратный запрещён.
@freezed
sealed class PlaybackState with _$PlaybackState {
  const factory initial() = PlaybackInitial;
  const factory playing({
    required Media media,
    required MediaType type,
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
    @Default(1.0) double speed,
    Duration? savedPosition,
  }) = PlaybackPlaying;
  const factory completed() = PlaybackCompleted;
  const factory loading() = PlaybackLoading;
  const factory error({required String message}) = PlaybackError;
}

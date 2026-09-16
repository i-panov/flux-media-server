import 'package:flutter/foundation.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Минимальный снимок состояния панели управления плеера: без position,
/// чтобы панель не пересоздавалась на каждый тик позиции.
enum PlayerViewKind { initial, loading, error, completed, playing }

@immutable
class PlayerView {
  const new({
    required this.kind,
    required this.media,
    required this.type,
    required this.isPaused,
    required this.savedPosition,
    required this.errorMessage,
  });

  final PlayerViewKind kind;
  final Media? media;
  final MediaType? type;
  final bool isPaused;
  final Duration? savedPosition;
  final String? errorMessage;

  // `==`/`hashCode` обязательны: `ref.watch(select(...))` сравнивает
  // результат через `!=` и без них каждый новый PlayerView (создаваемый на
  // каждый тик позиции, даже если поля не изменились) считался бы
  // изменённым → панель управления пересоздавалась бы на каждый тик.
  @override
  bool operator ==(Object other) {
    return other is PlayerView &&
        other.kind == kind &&
        other.media == media &&
        other.type == type &&
        other.isPaused == isPaused &&
        other.savedPosition == savedPosition &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode =>
      Object.hash(kind, media, type, isPaused, savedPosition, errorMessage);
}

/// Сопоставляет [PlaybackState] с минимальным снимком для панели управления.
///
/// Позиция намеренно не включается: она меняется на каждый тик таймера
/// (media_kit рисует прогресс сам), и слежка за ней пересоздавала бы панель.
PlayerView playerViewFromPlaybackState(PlaybackState state) {
  return switch (state) {
    PlaybackInitial() => const PlayerView(
      kind: PlayerViewKind.initial,
      media: null,
      type: null,
      isPaused: false,
      savedPosition: null,
      errorMessage: null,
    ),
    PlaybackLoading() => const PlayerView(
      kind: PlayerViewKind.loading,
      media: null,
      type: null,
      isPaused: false,
      savedPosition: null,
      errorMessage: null,
    ),
    PlaybackError(:final message) => PlayerView(
      kind: PlayerViewKind.error,
      media: null,
      type: null,
      isPaused: false,
      savedPosition: null,
      errorMessage: message,
    ),
    PlaybackCompleted() => const PlayerView(
      kind: PlayerViewKind.completed,
      media: null,
      type: null,
      isPaused: false,
      savedPosition: null,
      errorMessage: null,
    ),
    PlaybackPlaying(
      :final media,
      :final type,
      :final isPaused,
      :final savedPosition,
    ) =>
      PlayerView(
        kind: PlayerViewKind.playing,
        media: media,
        type: type,
        isPaused: isPaused,
        savedPosition: savedPosition,
        errorMessage: null,
      ),
  };
}

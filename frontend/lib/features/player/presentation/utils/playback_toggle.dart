import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';

/// Переключить воспроизведение по [mediaId].
///
/// Ключевая деталь: тап по СВОЕМУ треку идёт в паузу/продолжение, а по
/// чужому — запускает его. Логика копировалась в `audio_track_row` и
/// `audio_mini_player` и разошлась: мини-плеер умел только play/pause и не
/// переключал трек.
void togglePlayback(
  WidgetRef ref,
  int mediaId, {
  bool isPaused = false,
  void Function(int mediaId)? onStartOther,
}) {
  final playback = ref.read(playbackCoordinatorProvider);
  final isCurrent = playback is PlaybackPlaying && playback.media.id == mediaId;

  if (!isCurrent) {
    if (onStartOther != null) {
      onStartOther(mediaId);
      return;
    }
    // Stale-кадр (показан не текущий трек), а запускать нечего:
    // переключаем реальное воспроизведение, а не игнорируем тап молча.
    // Гард обязателен: в initial/loading/completed/error текущего трека
    // нет, и каст ниже упал бы с TypeError.
    if (playback is! PlaybackPlaying) return;
    final coordinator = ref.read(playbackCoordinatorProvider.notifier);
    final current = playback;
    unawaited(current.isPaused ? coordinator.resume() : coordinator.pause());
    return;
  }
  final coordinator = ref.read(playbackCoordinatorProvider.notifier);
  unawaited(isPaused ? coordinator.resume() : coordinator.pause());
}

/// Текущее состояние воспроизведения для [mediaId], чтобы подсветить
/// строку в списке: `null`, если играет другой трек.
({bool isPaused, bool isCurrent})? playbackStateOf(WidgetRef ref, int mediaId) {
  final playback = ref.read(playbackCoordinatorProvider);
  if (playback is! PlaybackPlaying || playback.media.id != mediaId) return null;
  return (isPaused: playback.isPaused, isCurrent: true);
}

/// Цель перемотки: `position + step`, ограниченная диапазоном
/// `[Duration.zero, duration]`.
///
/// Кнопки ±10с без клампа уводили позицию в минус (mpv получал
/// некорректный таргет) или за конец файла. Пока длительность неизвестна
/// (`Duration.zero`), ограничиваемся только снизу.
Duration clampSeekPosition({
  required Duration position,
  required Duration step,
  required Duration duration,
}) {
  final target = position + step;
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Один элемент аудио-плейлиста, готовый к открытию в media_kit.
///
/// Токен/локальный путь и обложка вычисляются один раз на элемент, а не
/// на каждый переход: mpv применяет `httpHeaders` сам при загрузке
/// каждого файла из плейлиста (см. media_kit `MPV_EVENT_FILE_LOADED`).
class AudioQueueEntry {
  const new({
    required this.mediaId,
    required this.url,
    required this.title,
    this.artist,
    this.artUri,
    this.duration,
    this.httpHeaders,
  });

  /// id трека в базе: по нему MediaItem уведомления сопоставляется с
  /// элементом плейлиста mpv (в самом mpv id нет — только uri).
  final int mediaId;

  final String url;
  final String title;
  final String? artist;

  /// URL обложки под авторизацией. Скачивается отдельно и уже после
  /// старта воспроизведения — в критическом пути перехода сети быть
  /// не должно.
  final String? artUri;
  final Duration? duration;
  final Map<String, String>? httpHeaders;
}

/// Абстракция аудио-плеера для PlaybackCoordinator.
/// Позволяет тестировать координатор без реального media_kit Player.
abstract class AudioPlaybackSource {
  /// Загружает весь плейлист в mpv одним вызовом и стартует с [startIndex].
  Future<void> loadPlaylist(
    List<AudioQueueEntry> entries, {
    required int startIndex,
  });

  /// Дописывает элементы в конец уже загруженного плейлиста, не прерывая
  /// текущее воспроизведение.
  Future<void> appendToPlaylist(List<AudioQueueEntry> entries);

  /// Следующий элемент плейлиста (одна mpv-команда, без переоткрытия).
  Future<void> next();
  Future<void> previous();
  Future<void> jump(int index);
  Future<void> remove(int index);

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// Индекс текущего элемента плейлиста по данным mpv.
  int get playlistIndex;

  /// Изменения индекса, которые инициировал mpv (в т.ч. авто-переход
  /// при доигрывании трека). Пусто, если плейлист не используется.
  Stream<int> get playlistIndexStream;

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;
  Stream<bool> get bufferingStream;
  Stream<double> get volumeStream;
  double get volume;
}

/// Абстракция видео-плеера для PlaybackCoordinator.
abstract class VideoPlaybackSource {
  /// Нижнеуровневый media_kit player (нужен VideoController и UI).
  Player get player;
  Future<void> open(String url, {Map<String, String>? httpHeaders});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;
  Stream<bool> get bufferingStream;
  Duration get position;
  double get rate;
  Stream<double> get rateStream;
}

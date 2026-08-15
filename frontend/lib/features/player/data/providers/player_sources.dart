import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Абстракция аудио-плеера для PlaybackCoordinator.
/// Позволяет тестировать координатор без реального media_kit Player.
abstract class AudioPlaybackSource {
  Future<void> loadSource({
    required String url,
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
    Map<String, String>? httpHeaders,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
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

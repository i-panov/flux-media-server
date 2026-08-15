import 'dart:async';

import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:media_kit/media_kit.dart';

/// Data source wrapping media_kit's [Player] for video playback.
class VideoPlayerDatasource implements VideoPlaybackSource {
  /// Creates a [VideoPlayerDatasource] with a new [Player] instance.
  VideoPlayerDatasource() : player = Player();

  /// The underlying media_kit player.
  @override
  final Player player;

  /// Opens a media stream from [url] with optional [httpHeaders].
  @override
  Future<void> open(String url, {Map<String, String>? httpHeaders}) async {
    await player.open(Media(url, httpHeaders: httpHeaders));
  }

  /// Starts or resumes playback.
  @override
  Future<void> play() async => player.play();

  /// Pauses playback.
  @override
  Future<void> pause() async => player.pause();

  /// Stops playback.
  @override
  Future<void> stop() async => player.stop();

  /// Seeks to the given [position].
  @override
  Future<void> seek(Duration position) async => player.seek(position);

  /// Sets playback rate.
  @override
  Future<void> setRate(double rate) async => player.setRate(rate);

  /// Current playback position.
  @override
  Duration get position => player.state.position;

  /// Current playback rate.
  @override
  double get rate => player.state.rate;

  /// Stream of playback rate changes.
  @override
  Stream<double> get rateStream => player.stream.rate;

  /// Stream of current playback position.
  @override
  Stream<Duration> get positionStream => player.stream.position;

  /// Stream of total media duration.
  @override
  Stream<Duration> get durationStream => player.stream.duration;

  /// Stream of playback state (playing/paused).
  @override
  Stream<bool> get playingStream => player.stream.playing;

  /// Stream that emits when playback completes.
  @override
  Stream<bool> get completedStream => player.stream.completed;

  /// Stream of playback errors (e.g. 401, unreachable stream).
  @override
  Stream<String> get errorStream => player.stream.error;

  /// Stream of buffering state.
  @override
  Stream<bool> get bufferingStream => player.stream.buffering;

  /// Disposes the player and frees resources.
  Future<void> dispose() async => player.dispose();
}

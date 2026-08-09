import 'dart:async';

import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:media_kit/media_kit.dart';

/// Data source wrapping [FluxAudioHandler] for audio playback.
/// Delegates to the audio handler's media_kit [Player] so that
/// playback state is synced with the system media notification.
class AudioPlayerDatasource {
  AudioPlayerDatasource(this._handler);

  final FluxAudioHandler _handler;

  /// The underlying media_kit player (for direct stream access).
  Player get player => _handler.player;

  Future<void> open(String url, {Map<String, String>? httpHeaders}) async =>
      _handler.player.open(Media(url, httpHeaders: httpHeaders));
  Future<void> play() async => _handler.play();
  Future<void> pause() async => _handler.pause();
  Future<void> stop() async => _handler.stop();
  Future<void> seek(Duration position) async => _handler.seek(position);
  Future<void> setVolume(double volume) async => _handler.setVolume(volume);
  Stream<Duration> get positionStream => _handler.positionStream;
  Stream<Duration> get durationStream => _handler.durationStream;
  Stream<bool> get playingStream => _handler.playingStream;
  Stream<double> get volumeStream => _handler.volumeStream;
  Stream<bool> get completedStream => _handler.completedStream;
  Future<void> dispose() async => _handler.dispose();

  /// Loads a media source with metadata for the system notification.
  Future<void> loadSource({
    required String url,
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
    Map<String, String>? httpHeaders,
  }) async {
    await _handler.loadSource(
      url: url,
      title: title,
      artist: artist,
      artUri: artUri,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }
}

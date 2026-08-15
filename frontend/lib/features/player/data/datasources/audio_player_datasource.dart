import 'dart:async';

import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:media_kit/media_kit.dart';

/// Data source wrapping [FluxAudioHandler] for audio playback.
/// Delegates to the audio handler's media_kit [Player] so that
/// playback state is synced with the system media notification.
class AudioPlayerDatasource implements AudioPlaybackSource {
  AudioPlayerDatasource(this._handler);

  final FluxAudioHandler _handler;

  /// The underlying media_kit player (for direct stream access).
  Player get player => _handler.player;

  Future<void> open(String url, {Map<String, String>? httpHeaders}) async =>
      _handler.player.open(Media(url, httpHeaders: httpHeaders));
  // Идём в обход FluxAudioHandler.play(): тот делегирует play из
  // системного уведомления через onPlay в координатор, а вызов отсюда
  // идёт уже из самого координатора (иначе — рекурсия).
  @override
  Future<void> play() async => _handler.player.play();
  @override
  Future<void> pause() async => _handler.pause();
  @override
  Future<void> stop() async => _handler.stop();
  @override
  Future<void> seek(Duration position) async => _handler.seek(position);
  @override
  Future<void> setVolume(double volume) async => _handler.setVolume(volume);
  @override
  Stream<Duration> get positionStream => _handler.positionStream;
  @override
  Stream<Duration> get durationStream => _handler.durationStream;
  @override
  Stream<bool> get playingStream => _handler.playingStream;
  @override
  Stream<double> get volumeStream => _handler.volumeStream;
  @override
  Stream<bool> get completedStream => _handler.completedStream;
  @override
  Stream<String> get errorStream => _handler.errorStream;
  @override
  Stream<bool> get bufferingStream => _handler.bufferingStream;
  @override
  double get volume => _handler.player.state.volume;
  Future<void> dispose() async => _handler.dispose();

  /// Loads a media source with metadata for the system notification.
  @override
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

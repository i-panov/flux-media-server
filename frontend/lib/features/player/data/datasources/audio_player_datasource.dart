import 'dart:async';

import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';

/// Data source wrapping [FluxAudioHandler] for audio playback.
///
/// Всё идёт через хендлер — он единственная точка маршрутизации команд.
/// К `engine` здесь обращаться не нужно и нельзя: у хендлера есть методы,
/// которые уводят в делегаты системного уведомления, и вызов их из
/// координатора замкнул бы цепочку сам на себя.
class AudioPlayerDatasource implements AudioPlaybackSource {
  new(this._handler);

  final FluxAudioHandler _handler;

  @override
  Future<void> loadPlaylist(
    List<AudioQueueEntry> entries, {
    required int startIndex,
  }) => _handler.loadPlaylist(entries, startIndex: startIndex);

  @override
  Future<void> appendToPlaylist(List<AudioQueueEntry> entries) =>
      _handler.appendToPlaylist(entries);

  @override
  Future<void> next() => _handler.next();

  @override
  Future<void> previous() => _handler.previous();

  @override
  Future<void> jump(int index) => _handler.jump(index);

  @override
  Future<void> remove(int index) => _handler.remove(index);

  @override
  Future<void> play() => _handler.playDirect();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<void> setVolume(double volume) => _handler.setVolume(volume);

  @override
  int get playlistIndex => _handler.playlistIndex;

  @override
  Stream<int> get playlistIndexStream => _handler.playlistIndexStream;

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration> get durationStream => _handler.durationStream;

  @override
  Stream<bool> get playingStream => _handler.playingStream;

  @override
  Stream<bool> get completedStream => _handler.completedStream;

  @override
  Stream<String> get errorStream => _handler.errorStream;

  @override
  Stream<bool> get bufferingStream => _handler.bufferingStream;

  @override
  Stream<double> get volumeStream => _handler.volumeStream;

  @override
  double get volume => _handler.volume;

  Future<void> dispose() => _handler.dispose();
}

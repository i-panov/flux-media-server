import 'package:media_kit/media_kit.dart';

/// Data source wrapping media_kit's [Player] for audio playback.
class AudioPlayerDatasource {
  AudioPlayerDatasource() : player = Player();

  final Player player;

  Future<void> open(String url) async => await player.open(Media(url));
  Future<void> play() async => player.play();
  Future<void> pause() async => player.pause();
  Future<void> stop() async => player.stop();
  Future<void> seek(Duration position) async => player.seek(position);
  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;
  Stream<bool> get playingStream => player.stream.playing;
  Stream<bool> get completedStream => player.stream.completed;
  Future<void> dispose() async => player.dispose();
}

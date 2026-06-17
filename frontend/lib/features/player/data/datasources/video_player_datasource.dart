import 'package:media_kit/media_kit.dart';

class VideoPlayerDatasource {
  VideoPlayerDatasource() : player = Player();

  final Player player;

  Future<void> open(String url) async {
    await player.open(Media(url));
  }

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  Stream<Duration> get positionStream => player.position;
  Stream<Duration?> get durationStream => player.duration;
  Stream<bool> get playingStream => player.playing;
  Stream<PlayerState> get playerStateStream => player.stream.playerState;

  Future<void> dispose() async {
    await player.dispose();
  }
}

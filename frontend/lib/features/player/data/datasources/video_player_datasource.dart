import 'package:media_kit/media_kit.dart';

/// Data source wrapping media_kit's [Player] for video playback.
class VideoPlayerDatasource {
  /// Creates a [VideoPlayerDatasource] with a new [Player] instance.
  VideoPlayerDatasource() : player = Player();

  /// The underlying media_kit player.
  final Player player;

  /// Opens a media stream from [url].
  Future<void> open(String url) async {
    await player.open(Media(url));
  }

  /// Starts or resumes playback.
  Future<void> play() async => player.play();

  /// Pauses playback.
  Future<void> pause() async => player.pause();

  /// Seeks to the given [position].
  Future<void> seek(Duration position) async => player.seek(position);

  /// Stream of current playback position.
  Stream<Duration> get positionStream => player.stream.position;

  /// Stream of total media duration.
  Stream<Duration> get durationStream => player.stream.duration;

  /// Stream of playback state (playing/paused).
  Stream<bool> get playingStream => player.stream.playing;

  /// Stream that emits when playback completes.
  Stream<bool> get completedStream => player.stream.completed;

  /// Disposes the player and frees resources.
  Future<void> dispose() async => player.dispose();
}

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Audio handler that wraps media_kit's [Player] and integrates with
/// the system media notification, lock screen controls, and background
/// audio playback via `audio_service`.
///
/// The underlying [Player] is exposed so that UI widgets (e.g. volume
/// slider, seek bar) can subscribe to its streams directly.
class FluxAudioHandler extends BaseAudioHandler with SeekHandler {
  FluxAudioHandler() : player = Player() {
    unawaited(_init());
  }

  /// The media_kit player used for actual audio playback.
  final Player player;

  /// Callbacks wired up from the play queue by `main.dart`.
  Future<bool> Function()? onNext;
  Future<bool> Function()? onPrevious;
  void Function()? onToggleFavorite;

  /// Делегат для play из системного уведомления. Маршрутизируется через
  /// координатор (см. main.dart), чтобы состояние UI не расходилось с
  /// реальным воспроизведением (например, play после completed должен
  /// перезапускать трек, а не играть «в фоне» с состоянием completed).
  Future<void> Function()? onPlay;

  /// Whether the current track is favorited (for notification icon).
  bool isFavorite = false;

  /// Играл ли трек до прерывания (звонок и т.п.) — для resume.
  bool _wasPlayingBeforeInterruption = false;

  StreamSubscription<dynamic>? _interruptionSub;
  StreamSubscription<dynamic>? _noisySub;

  static const _controlsPlaying = [
    MediaControl.skipToPrevious,
    MediaControl.pause,
    MediaControl.skipToNext,
  ];

  static const _controlsPaused = [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.skipToNext,
  ];

  Future<void> _init() async {
    // Аудиофокус: пауза при звонках/других приложениях, пауза при
    // отключении наушников (becomingNoisy).
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _wasPlayingBeforeInterruption = player.state.playing;
          unawaited(player.pause());
        } else if (event.type == AudioInterruptionType.pause &&
            _wasPlayingBeforeInterruption) {
          _wasPlayingBeforeInterruption = false;
          unawaited(player.play());
        }
      });
      _noisySub =
          session.becomingNoisyEventStream.listen((_) => player.pause());
    } catch (e) {
      // audio_session может быть недоступен на некоторых платформах —
      // воспроизведение продолжает работать без обработки фокуса.
      // ignore: avoid_print
      print('AudioSession init failed: $e');
    }

    player.stream.playing.listen((playing) {
      final controls = playing ? _controlsPlaying : _controlsPaused;
      final state = playbackState.value.copyWith(
        playing: playing,
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        processingState: AudioProcessingState.ready,
      );
      playbackState.add(state);
    });

    player.stream.position.listen((position) {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: position,
        ),
      );
    });

    player.stream.duration.listen((duration) {
      final item = mediaItem.value;
      if (item != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });

    player.stream.completed.listen((completed) {
      if (completed) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.completed,
          ),
        );
      }
    });
  }

  /// Loads a media source and sets the [MediaItem] metadata for the
  /// system notification.
  ///
  /// If [artUri] requires authentication, the image is downloaded with
  /// [httpHeaders] to a temporary file and a `file://` URI is used instead,
  /// because audio_service's internal image fetcher doesn't send auth headers.
  Future<void> loadSource({
    required String url,
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
    Map<String, String>? httpHeaders,
  }) async {
    Uri? resolvedArtUri;
    if (artUri != null) {
      resolvedArtUri = await _resolveArtUri(artUri, httpHeaders);
    }

    final item = MediaItem(
      id: url,
      title: title,
      artist: artist,
      artUri: resolvedArtUri,
      duration: duration,
    );
    mediaItem.add(item);
    await player.open(Media(url, httpHeaders: httpHeaders));
  }

  /// Downloads [artUri] with auth headers to a temp file and returns a
  /// `file://` URI. Falls back to the original URI on failure.
  ///
  /// Имя файла содержит хеш URL: для одного трека файл перезаписывается
  /// (стабильный кеш), коллизии между треками с одинаковыми путями
  /// (`/media/{id}/cover`) исключены. Старые обложки других треков
  /// удаляются при записи новой.
  Future<Uri?> _resolveArtUri(
    String artUri,
    Map<String, String>? httpHeaders,
  ) async {
    final uri = Uri.tryParse(artUri);
    if (uri == null || !uri.scheme.startsWith('http')) {
      return uri;
    }

    try {
      final response = await http
          .get(uri, headers: httpHeaders ?? {})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return uri;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_artFileName(uri)}');
      await _cleanupArtwork(dir, keep: file);
      await file.writeAsBytes(response.bodyBytes);
      return file.uri;
    } catch (_) {
      return uri;
    }
  }

  String _artFileName(Uri uri) {
    final hash = uri.toString().hashCode.abs().toRadixString(16);
    return 'flux_art_${uri.pathSegments.last}_$hash.jpg';
  }

  /// Best-effort: удаляет устаревшие обложки, оставляя только [keep].
  Future<void> _cleanupArtwork(Directory dir, {required File keep}) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('flux_art_') && entity.path != keep.path) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Не критично — мусорные файлы удалятся при следующей загрузке.
    }
  }

  @override
  Future<void> play() async {
    if (onPlay != null) {
      // Play из системного уведомления: маршрутизируем через координатор.
      await onPlay!();
    } else {
      await player.play();
    }
  }

  @override
  Future<void> pause() async {
    await player.pause();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (onNext != null) {
      await onNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevious != null) {
      await onPrevious!();
    }
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'toggleFavorite') {
      onToggleFavorite?.call();
      return null;
    }
    return super.customAction(name, extras);
  }

  Future<void> setVolume(double volume) async {
    await player.setVolume(volume);
  }

  Stream<double> get volumeStream => player.stream.volume;
  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;
  Stream<bool> get playingStream => player.stream.playing;
  Stream<bool> get completedStream => player.stream.completed;
  Stream<String> get errorStream => player.stream.error;
  Stream<bool> get bufferingStream => player.stream.buffering;

  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await player.dispose();
  }
}

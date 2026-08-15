import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/datasources/audio_player_datasource.dart';
import 'package:flux_media_server/features/player/data/datasources/video_player_datasource.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_coordinator.freezed.dart';

@freezed
class PlaybackState with _$PlaybackState {
  const factory PlaybackState.initial() = PlaybackInitial;
  const factory PlaybackState.playing({
    required Media media,
    required MediaType type,
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    Duration? duration,
    @Default(1.0) double speed,
    Duration? savedPosition,
  }) = PlaybackPlaying;
  const factory PlaybackState.completed() = PlaybackCompleted;
  const factory PlaybackState.loading() = PlaybackLoading;
  const factory PlaybackState.error({required String message}) = PlaybackError;
}

/// Manages unified playback across audio and video.
/// Handles mutual exclusion: starting video stops audio and vice versa.
class PlaybackCoordinator extends Notifier<PlaybackState>
    implements PlaybackController {
  late final AudioPlaybackSource _audioPlayer;
  late final String _baseUrl;

  @override
  PlaybackState build() {
    _audioPlayer = ref.watch(audioPlayerDatasourceProvider);
    _baseUrl = ref.watch(baseUrlProvider);
    // В Notifier (Riverpod 2.x) нет переопределяемого dispose() —
    // cleanup при утилизации провайдера делаем через onDispose.
    ref.onDispose(() {
      _cancelSubscriptions();
      _cancelProgressTimer();
    });
    return const PlaybackState.initial();
  }

  /// Порог для resume-оверлея: позиции не больше этого значения
  /// применяются сразу (видео продолжается без диалога).
  static const _resumeThreshold = Duration(seconds: 5);

  /// Интервал автосохранения прогресса во время воспроизведения.
  static const _progressSaveInterval = Duration(seconds: 10);

  /// Последний начатый тип медиа. Нужен в stop(): при loading/completed
  /// состояние не хранит тип, а остановить физический плеер всё равно
  /// необходимо (например, закрытие экрана во время загрузки видео).
  MediaType? _lastType;

  /// Поколение play-операций: инкрементируется при каждом play/stop.
  /// _playInternal проверяет его после каждого await — если stop() или
  /// новый play прервал операцию (например, экран закрыт во время
  /// PlaybackLoading), незавершённый open()/play() не должен перезапускать
  /// воспроизведение и переписывать состояние.
  int _playGeneration = 0;

  /// Used to lazily read the current auth token (so token refreshes don't
  /// reset the playback state) and to coordinate with the video player.
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;

  /// Lazily reads the video player datasource. Using ref.read instead of
  /// ref.watch prevents this long-lived provider from keeping the
  /// autoDispose videoPlayerDatasourceProvider alive.
  VideoPlaybackSource get _videoPlayer =>
      ref.read(videoPlayerDatasourceProvider);

  /// Сериализует сохранения прогресса: параллельные вызовы (completed
  /// при завершении трека, save таймера, сохранение предыдущего трека
  /// при переключении) выполняются строго по очереди, чтобы более
  /// позднее сохранение не перезаписало более раннее (гонка
  /// completed:true vs completed:false).
  Future<void> _saveChain = Future.value();

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _cancelProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// Serializes concurrent play() calls through a Future chain: each call
  /// waits for the previous one to finish, ensuring only the latest media
  /// actually starts playing. Errors are swallowed in the chain itself
  /// (otherwise one failed play would block all subsequent calls), while
  /// each caller still receives its own result.
  Future<void> _playChain = Future.value();

  /// Starts playback of [media]. Stops any current playback first.
  /// Serializes concurrent play() calls to prevent race conditions.
  @override
  Future<void> play(Media media) {
    final result = _playChain.then((_) => _guardedPlay(media));
    _playChain = result.catchError((_) {});
    return result;
  }

  /// Runs [_playInternal] and converts failures into [PlaybackState.error].
  Future<void> _guardedPlay(Media media) async {
    try {
      state = const PlaybackState.loading();
      await _playInternal(media);
    } catch (e) {
      state = PlaybackState.error(message: e.toString());
      rethrow;
    }
  }

  Future<void> _playInternal(Media media) async {
    final generation = ++_playGeneration;
    _lastType = media.type;
    // Save progress of the current playback before switching.
    // Не сохраняется при автопродвижении: _onCompleted уже отправил
    // completed:true и перевёл состояние в loading (иначе гонка
    // completed:true vs completed:false).
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }

    _cancelSubscriptions();
    _cancelProgressTimer();

    // Use local file if downloaded, otherwise stream from server.
    final cacheService = ref.read(offlineCacheServiceProvider);
    final localPath = await cacheService.getLocalPath(media.id);
    if (generation != _playGeneration) return;
    final url = localPath ?? '$_baseUrl/media/${media.id}/stream';
    final token = ref.read(settingsProvider).settings.authToken;
    final headers = localPath == null && token != null
        ? <String, String>{'Authorization': 'Bearer $token'}
        : null;

    if (media.type == MediaType.audio) {
      // Mutual exclusion: stop video playback before starting audio.
      await _videoPlayer.stop();

      // Build cover art URL for system notification.
      // Skip when offline — no server to fetch from.
      String? coverUrl;
      if (localPath == null) {
        coverUrl = (media.coverUrl != null && media.coverUrl!.isNotEmpty)
            ? '$_baseUrl/media/${media.id}/cover'
            : (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty
                ? '$_baseUrl/media/${media.id}/thumb'
                : null);
      }

      // Start audio playback with metadata for the system notification.
      await _audioPlayer.loadSource(
        url: url,
        title: media.title,
        artist: media.artists.map((a) => a.name).join(', '),
        artUri: coverUrl,
        duration:
            media.duration != null ? Duration(seconds: media.duration!) : null,
        httpHeaders: headers,
      );
      if (generation != _playGeneration) return;
      await _audioPlayer.play();
      if (generation != _playGeneration) return;

      state = PlaybackState.playing(
        media: media,
        type: MediaType.audio,
      );

      _subscribeToStream(_audioPlayer.positionStream, (pos) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(position: pos);
        }
      });
      _subscribeToStream(_audioPlayer.durationStream, (dur) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(duration: dur);
        }
      });
      _subscribeToStream(_audioPlayer.playingStream, (playing) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(isPaused: !playing);
        }
      });
      _subscribeToStream(_audioPlayer.completedStream, _onCompleted);
      _subscribeToStream(_audioPlayer.errorStream, _onPlayerError);
      _subscribeToStream(_audioPlayer.bufferingStream, _onBuffering);
    } else {
      // Mutual exclusion: stop audio playback before starting video.
      await _audioPlayer.stop();

      // Start video playback
      await _videoPlayer.open(url, httpHeaders: headers);
      if (generation != _playGeneration) return;
      await _videoPlayer.play();
      if (generation != _playGeneration) return;

      // Load saved position for resume dialog (video only).
      final resumePosition = await _loadSavedPosition(media.id);
      if (generation != _playGeneration) return;

      state = PlaybackState.playing(
        media: media,
        type: MediaType.video,
        savedPosition:
            resumePosition != null && resumePosition > _resumeThreshold
                ? resumePosition
                : null,
      );

      if (resumePosition != null && resumePosition <= _resumeThreshold) {
        await _videoPlayer.seek(resumePosition);
      }

      _subscribeToStream(_videoPlayer.positionStream, (pos) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(position: pos);
        }
      });
      _subscribeToStream(_videoPlayer.durationStream, (dur) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(duration: dur);
        }
      });
      _subscribeToStream(_videoPlayer.playingStream, (playing) {
        if (state is PlaybackPlaying) {
          state = (state as PlaybackPlaying).copyWith(isPaused: !playing);
        }
      });
      _subscribeToStream(_videoPlayer.completedStream, _onCompleted);
      _subscribeToStream(_videoPlayer.errorStream, _onPlayerError);
      _subscribeToStream(_videoPlayer.bufferingStream, _onBuffering);
    }

    _startProgressTimer();
  }

  Future<void> _onCompleted(bool completed) async {
    if (!completed) return;
    final current = state;
    if (current is PlaybackPlaying) {
      // Await: сериализованное сохранение должно завершиться до старта
      // следующего трека, иначе _playInternal может отправить
      // completed:false поверх completed:true.
      await _saveProgress(
        current.media.id,
        current.duration ?? current.position,
        current.duration ?? Duration.zero,
        completed: true,
      );
    }
    _cancelProgressTimer();

    // Don't auto-advance if we're in loading state (user switched tracks).
    if (state is PlaybackLoading) return;

    // Auto-advance to next track in queue if available.
    final queue = ref.read(playQueueProvider);
    if (queue.hasNext) {
      // Фиксируем завершённость до старта следующего трека: loading
      // исключает повторное сохранение предыдущего в _playInternal.
      state = const PlaybackState.loading();
      await ref.read(playQueueProvider.notifier).next();
    } else {
      state = const PlaybackState.completed();
    }
  }

  /// Handles player errors (e.g. 401, unreachable stream).
  void _onPlayerError(String error) {
    if (state is PlaybackPlaying || state is PlaybackLoading) {
      state = PlaybackState.error(message: error);
    }
  }

  /// Handles buffering state changes.
  void _onBuffering(bool buffering) {
    // media_kit emits buffering events frequently; we don't want to
    // change state on every tick. The UI can subscribe to the stream
    // directly if it needs a buffering indicator.
  }

  void _subscribeToStream<T>(Stream<T> stream, void Function(T) onNext) {
    final sub = stream.listen(onNext);
    _subscriptions.add(sub);
  }

  /// Returns the saved watch position for [mediaId], or null if there is
  /// none (or the media was already completed).
  Future<Duration?> _loadSavedPosition(int mediaId) async {
    final result = await ref.read(mediaRepositoryProvider).getProgress();
    return result.fold(
      (_) => null,
      (progressList) {
        for (final p in progressList) {
          if (p.mediaId == mediaId && p.position > 0) {
            return Duration(seconds: p.position);
          }
        }
        return null;
      },
    );
  }

  /// Saves watch progress to the backend. Best-effort: errors are logged
  /// and ignored. Отправляет duration и completed — бэкенд их принимает
  /// и сохраняет. Вызовы сериализуются через [_saveChain].
  Future<void> _saveProgress(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) {
    final result = _saveChain.then(
      (_) => _doSaveProgress(
        mediaId,
        position,
        duration,
        completed: completed,
      ),
    );
    _saveChain = result.catchError((_) {});
    return result;
  }

  Future<void> _doSaveProgress(
    int mediaId,
    Duration position,
    Duration duration, {
    bool? completed,
  }) async {
    if (position <= Duration.zero) return;
    try {
      await ref.read(mediaRepositoryProvider).updateProgress(
            mediaId,
            position: position.inSeconds,
            duration: duration.inSeconds,
            completed: completed ?? false,
          );
    } on Exception catch (e) {
      developer.log('Failed to save progress: $e');
    }
  }

  /// Periodically persists watch progress while playing.
  void _startProgressTimer() {
    _cancelProgressTimer();
    _progressTimer =
        Timer.periodic(_progressSaveInterval, (_) {
      final current = state;
      if (current is PlaybackPlaying && !current.isPaused) {
        unawaited(
          _saveProgress(
            current.media.id,
            current.position,
            current.duration ?? Duration.zero,
          ),
        );
      }
    });
  }

  Future<void> pause() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.pause();
      } else {
        await _videoPlayer.pause();
      }
      state = current.copyWith(isPaused: true);
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }
  }

  Future<void> resume() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.play();
      } else {
        await _videoPlayer.play();
      }
      state = current.copyWith(isPaused: false);
    }
  }

  Future<void> seek(Duration position) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.audio) {
        await _audioPlayer.seek(position);
      } else {
        await _videoPlayer.seek(position);
      }
    }
  }

  /// Sets playback speed (video only).
  Future<void> setSpeed(double speed) async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      if (current.media.type == MediaType.video) {
        await _videoPlayer.setRate(speed);
        state = current.copyWith(speed: speed);
      }
    }
  }

  /// Seeks to the saved position (from the resume dialog).
  Future<void> seekToSavedPosition() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      final saved = current.savedPosition;
      if (saved != null) {
        await _videoPlayer.seek(saved);
        state = current.copyWith(savedPosition: null);
      }
    }
  }

  /// Starts playback from the beginning (from the resume dialog).
  Future<void> startFromBeginning() async {
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _videoPlayer.seek(Duration.zero);
      state = current.copyWith(savedPosition: null);
    }
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  @override
  Future<void> stop() async {
    // Прерываем незавершённые play-операции (например, закрытие экрана
    // во время PlaybackLoading): _playInternal на ближайшей проверке
    // поколения выйдет и не запустит воспроизведение после stop.
    _playGeneration++;
    _cancelSubscriptions();
    _cancelProgressTimer();
    if (state is PlaybackPlaying) {
      final current = state as PlaybackPlaying;
      await _saveProgress(
        current.media.id,
        current.position,
        current.duration ?? Duration.zero,
      );
    }
    // Останавливаем физический плеер независимо от состояния (в т.ч.
    // loading/completed): при loading видео уже может играть после open(),
    // а при completed аудио нужно убрать системное уведомление.
    switch (_lastType) {
      case MediaType.audio:
        await _audioPlayer.stop();
      case MediaType.video:
        await _videoPlayer.stop();
      case MediaType.unknown:
      case null:
        break;
    }
    _lastType = null;
    state = const PlaybackState.initial();
  }

  Future<void> reset() async {
    await stop();
  }
}

/// Provider for the audio handler (initialized in main.dart via
/// AudioService.init).
final audioHandlerProvider = Provider<FluxAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in main()');
});

/// Provider for audio player datasource.
final audioPlayerDatasourceProvider = Provider<AudioPlaybackSource>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final ds = AudioPlayerDatasource(handler);
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for video player datasource.
/// NOT autoDispose: the PlaybackCoordinator holds it via ref.read across
/// multiple await points. If it were autoDispose, the player could be
/// disposed and recreated between open() and play(), causing operations
/// on different player instances.
final videoPlayerDatasourceProvider = Provider<VideoPlaybackSource>((ref) {
  final ds = VideoPlayerDatasource();
  ref.onDispose(ds.dispose);
  return ds;
});

/// Provider for playback coordinator.
final playbackCoordinatorProvider =
    NotifierProvider<PlaybackCoordinator, PlaybackState>(
  PlaybackCoordinator.new,
);

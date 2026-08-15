import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Видеоконтроллер живёт столько же, сколько видео-плеер (синглтон),
/// поэтому провайдер НЕ autoDispose: media_kit_video 1.3.x не умеет
/// безопасно пересоздавать контроллер на том же `Player` (ручной dispose
/// нотифаеров/нативного контроллера ломает [Video]-виджет, а повторное
/// создание — гонки с открытием потока). Один контроллер на плеер —
/// штатная модель media_kit: текстура переиспользуется между видео,
/// нативная часть освобождается при dispose плеера.
final videoControllerProvider = Provider<VideoController>((ref) {
  final datasource = ref.watch(videoPlayerDatasourceProvider);
  // Disable hardware acceleration on Linux — GPU rendering is unreliable
  // without CUDA/proprietary drivers (causes blue screen).
  return VideoController(
    datasource.player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !Platform.isLinux,
    ),
  );
});

/// Seek bar theme shared by mobile and fullscreen.
const _seekBarTheme = MaterialVideoControlsThemeData(
  seekBarHeight: 5,
  seekBarThumbSize: 20,
  seekBarMargin: EdgeInsets.only(left: 12, right: 12),
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 24),
  seekBarPositionColor: Colors.deepPurple,
  seekBarThumbColor: Colors.deepPurple,
  seekBarBufferColor: Color(0x66FFFFFF),
  seekBarColor: Color(0x33FFFFFF),
);

/// Скорости воспроизведения: от [_minSpeed] до [_maxSpeed] шагом [_speedStep].
const _minSpeed = .5;
const _maxSpeed = 2.0;
const _speedStep = 0.5;

/// Шаг перемотки ±N секунд.
const _seekStep = Duration(seconds: 10);

@RoutePage()
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.media, super.key});

  final Media media;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final PlaybackCoordinator _coordinator;

  /// Последний начатый тип воспроизведения. Обновляется через
  /// ref.listen (в dispose() обращаться к ref уже нельзя). По нему
  /// решаем, останавливать ли воспроизведение при закрытии экрана:
  /// видео — останавливаем всегда, аудио оставляем мини-плееру.
  MediaType? _lastPlaybackType;

  /// Shows a semi-transparent "resume" button when a saved position exists.
  bool _showResumeButton = false;
  Timer? _resumeTimer;

  /// Auto-hide delay for the resume button.
  static const _resumeHideDelay = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(playbackCoordinatorProvider.notifier);
    // Создаём VideoController сразу при открытии экрана (до перехода в
    // PlaybackPlaying): нативная текстура должна прикрепиться к плееру до
    // старта open(), иначе первый кадр может не отобразиться (чёрный
    // экран со звуком).
    ref.read(videoControllerProvider);
    final initial = ref.read(playbackCoordinatorProvider);
    if (initial is PlaybackPlaying) {
      _lastPlaybackType = initial.type;
    }
    // listenManual — вне build (в initState) ref.listen запрещён.
    ref.listenManual(playbackCoordinatorProvider, (previous, next) {
      if (next is PlaybackPlaying) {
        _lastPlaybackType = next.type;
      }
    });
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Allow all orientations — video aspect ratio determines the best fit.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playback = ref.read(playbackCoordinatorProvider);
      final alreadyPlaying = playback is PlaybackPlaying &&
          playback.type == MediaType.video &&
          playback.media.id == widget.media.id;
      if (!alreadyPlaying) {
        // Use setQueue so the queue is in sync with what's playing.
        // Without this, _onCompleted would jump to a stale queue item.
        ref.read(playQueueProvider.notifier).setQueue([widget.media]);
      }
    });
  }

  /// При сворачивании приложения паузим видео.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final playback = ref.read(playbackCoordinatorProvider);
    if (playback is PlaybackPlaying &&
        playback.type == MediaType.video &&
        !playback.isPaused) {
      unawaited(_coordinator.pause());
    }
  }

  void _showResumeOverlay(Duration savedPosition) {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    setState(() => _showResumeButton = true);
    _resumeTimer = Timer(_resumeHideDelay, () {
      _resumeTimer = null;
      if (mounted) setState(() => _showResumeButton = false);
    });
  }

  void _onResumeTap() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    setState(() => _showResumeButton = false);
    unawaited(_coordinator.seekToSavedPosition());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    // Останавливаем видео всегда (в т.ч. если экран закрыт во время
    // PlaybackLoading — иначе видео играет без UI). Аудио не трогаем:
    // оно продолжает играть в мини-плеере.
    if (_lastPlaybackType != MediaType.audio) {
      unawaited(_coordinator.stop());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Не следим за position: панель управления не должна пересоздаваться
    // на каждый тик таймера позиции (media_kit рисует прогресс сам).
    final view = ref.watch(
      playbackCoordinatorProvider.select((state) => switch (state) {
        PlaybackInitial() => const _View(
            kind: _ViewKind.initial,
            media: null,
            type: null,
            isPaused: false,
            savedPosition: null,
            errorMessage: null,
          ),
        PlaybackLoading() => const _View(
            kind: _ViewKind.loading,
            media: null,
            type: null,
            isPaused: false,
            savedPosition: null,
            errorMessage: null,
          ),
        PlaybackError(:final message) => _View(
            kind: _ViewKind.error,
            media: null,
            type: null,
            isPaused: false,
            savedPosition: null,
            errorMessage: message,
          ),
        PlaybackCompleted() => const _View(
            kind: _ViewKind.completed,
            media: null,
            type: null,
            isPaused: false,
            savedPosition: null,
            errorMessage: null,
          ),
        PlaybackPlaying(
          :final media,
          :final type,
          :final isPaused,
          :final savedPosition,
        ) => _View(
            kind: _ViewKind.playing,
            media: media,
            type: type,
            isPaused: isPaused,
            savedPosition: savedPosition,
            errorMessage: null,
          ),
        _ => const _View(
            kind: _ViewKind.initial,
            media: null,
            type: null,
            isPaused: false,
            savedPosition: null,
            errorMessage: null,
          ),
      },
    ),
  );

    // Show resume button once when savedPosition is set.
    if (view.kind == _ViewKind.playing &&
        view.type == MediaType.video &&
        view.savedPosition != null &&
        !_showResumeButton &&
        _resumeTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResumeOverlay(view.savedPosition!);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (view.kind) {
        _ViewKind.initial => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        _ViewKind.loading => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        _ViewKind.error => _ErrorView(
            message: view.errorMessage ?? '',
            media: widget.media,
          ),
        _ViewKind.completed => _CompletedView(media: widget.media),
        _ViewKind.playing => _buildPlaying(
            l,
            view.media!,
            view.type!,
            view.isPaused,
            view.savedPosition,
          ),
      },
    );
  }

  Widget _buildPlaying(
    AppLocalizations l,
    Media media,
    MediaType type,
    bool isPaused,
    Duration? savedPosition,
  ) {
    if (type != MediaType.video) {
      // Авто-переход на аудио-трек: вместо бесконечного спиннера
      // показываем осмысленное состояние и кнопку «назад».
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.music_note,
              size: 64,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            Text(
              media.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.audioPlayingInBackground,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.maybePop(),
              child: Text(l.close),
            ),
          ],
        ),
      );
    }

    // Build controls theme with custom buttons (back, ±10s, speed)
    // integrated into media_kit's button bars. This avoids a
    // full-screen GestureDetector that would intercept taps meant
    // for the built-in play/pause button.
    final isMobile = Platform.isAndroid || Platform.isIOS;

    final mobileTheme = _seekBarTheme.copyWith(
      // Back button stays in the top bar.
      topButtonBar: [const _BackButton()],
      // ±10s + speed in the bottom bar, centered via Spacers so they
      // don't stick to the left edge and cover the seek bar.
      bottomButtonBar: [
        const Spacer(),
        const _SeekButton(direction: -1),
        const _SeekButton(direction: 1),
        const _SpeedButton(),
        const SizedBox(width: 16),
        const Spacer(),
        const MaterialPositionIndicator(),
        const MaterialFullscreenButton(),
      ],
    );

    // Desktop: use copyWith to preserve the default bottom button bar
    // (skip, play/pause, volume, fullscreen) and insert ±10s + speed
    // right after the volume button — to the right of play/pause.
    final desktopTheme =
        const MaterialDesktopVideoControlsThemeData().copyWith(
      topButtonBar: [const _BackButton()],
      bottomButtonBar: [
        const MaterialDesktopSkipPreviousButton(),
        const MaterialDesktopPlayOrPauseButton(),
        const MaterialDesktopSkipNextButton(),
        const MaterialDesktopVolumeButton(),
        const _SeekButton(direction: -1),
        const _SeekButton(direction: 1),
        const _SpeedButton(),
        const SizedBox(width: 16),
        const MaterialDesktopPositionIndicator(),
        const Spacer(),
        const MaterialDesktopFullscreenButton(),
      ],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: MaterialVideoControlsTheme(
            normal: mobileTheme,
            fullscreen: mobileTheme,
            child: MaterialDesktopVideoControlsTheme(
              normal: desktopTheme,
              fullscreen: desktopTheme,
              child: Video(
                controller: ref.watch(videoControllerProvider),
                controls: isMobile
                    ? MaterialVideoControls
                    : MaterialDesktopVideoControls,
              ),
            ),
          ),
        ),
        // Semi-transparent resume button — appears above the controls
        // bar for a few seconds, then auto-hides.
        if (_showResumeButton && savedPosition != null)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _showResumeButton ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _onResumeTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.continueFrom(savedPosition.formatted),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Минимальный снимок состояния для build: без position, чтобы панель
/// управления не пересоздавалась на каждый тик позиции.
enum _ViewKind { initial, loading, error, completed, playing }

class _View {
  const _View({
    required this.kind,
    required this.media,
    required this.type,
    required this.isPaused,
    required this.savedPosition,
    required this.errorMessage,
  });

  final _ViewKind kind;
  final Media? media;
  final MediaType? type;
  final bool isPaused;
  final Duration? savedPosition;
  final String? errorMessage;
}

/// Назад: паузим видео и закрываем экран.
class _BackButton extends ConsumerWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      color: Colors.white,
      icon: const Icon(Icons.arrow_back),
      tooltip: l.mediaDetail,
      onPressed: () async {
        await ref.read(playbackCoordinatorProvider.notifier).pause();
        if (context.mounted) await context.maybePop();
      },
    );
  }
}

/// Перемотка ±[_seekStep] относительно текущей позиции плеера.
/// Читает позицию напрямую из плеера: значение в PlaybackState
/// обновляется через стрим и может отставать, из-за чего повторные
/// тапы искали бы от устаревшей позиции.
class _SeekButton extends ConsumerWidget {
  const _SeekButton({required this.direction});

  /// -1 — назад, 1 — вперёд.
  final int direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.read(playbackCoordinatorProvider.notifier);
    return IconButton(
      color: Colors.white,
      icon: Icon(direction < 0 ? Icons.replay_10 : Icons.forward_10),
      iconSize: 24,
      tooltip: direction < 0 ? '-10s' : '+10s',
      onPressed: () {
        final position =
            ref.read(videoPlayerDatasourceProvider).position;
        coordinator.seek(
          position + Duration(seconds: _seekStep.inSeconds * direction),
        );
      },
    );
  }
}

/// Кнопка скорости. Подписка на rateStream создаётся один раз
/// в initState: media_kit контролы не пересобираются при смене темы,
/// поэтому надпись должна обновляться через стрим, но без новой
/// подписки на каждый rebuild панели.
class _SpeedButton extends ConsumerStatefulWidget {
  const _SpeedButton();

  @override
  ConsumerState<_SpeedButton> createState() => _SpeedButtonState();
}

class _SpeedButtonState extends ConsumerState<_SpeedButton> {
  StreamSubscription<double>? _rateSub;
  double _rate = 1;

  @override
  void initState() {
    super.initState();
    final video = ref.read(videoPlayerDatasourceProvider);
    _rate = video.rate;
    _rateSub = video.rateStream.listen((rate) {
      if (mounted) setState(() => _rate = rate);
    });
  }

  @override
  void dispose() {
    _rateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      color: Colors.white,
      icon: Text(
        '${_rate}x',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
        ),
      ),
      tooltip: l.speed,
      onPressed: () {
        final next = _rate >= _maxSpeed ? _minSpeed : _rate + _speedStep;
        ref.read(playbackCoordinatorProvider.notifier).setSpeed(next);
      },
    );
  }
}

/// Состояние ошибки: сообщение + повтор и «назад».
class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message, required this.media});

  final String message;
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                ref.read(playQueueProvider.notifier).setQueue([media]);
              },
              child: Text(l.retry),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.maybePop(),
              child: Text(l.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// Состояние завершения: replay + «назад».
class _CompletedView extends ConsumerWidget {
  const _CompletedView({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.replay, size: 64, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                l.playbackCompleted,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref
                      .read(playQueueProvider.notifier)
                      .setQueue([media]);
                },
                child: Text(l.replay),
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.maybePop(),
          ),
        ),
      ],
    );
  }
}

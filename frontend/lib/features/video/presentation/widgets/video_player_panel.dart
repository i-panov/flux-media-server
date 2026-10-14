import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/core/utils/media_image_url.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_view.dart';
import 'package:flux_media_server/features/player/presentation/utils/playback_toggle.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Seek bar styling shared with the (deleted) fullscreen player.
const _seekBarBaseTheme = MaterialVideoControlsThemeData(
  seekBarHeight: 5,
  seekBarThumbSize: 20,
  seekBarMargin: EdgeInsets.only(left: 12, right: 12),
  seekBarPositionColor: Colors.deepPurple,
  seekBarThumbColor: Colors.deepPurple,
  seekBarBufferColor: Color(0x66FFFFFF),
  seekBarColor: Color(0x33FFFFFF),
);

const _minSpeed = .5;
const _maxSpeed = 2.0;
const _speedStep = 0.5;
const _seekStep = Duration(seconds: 10);

/// Видеоконтроллер живёт столько же, сколько видео-плеер (синглтон).
/// Без onDispose: у VideoController нет dispose, а плеер чистит
/// videoPlayerDatasourceProvider.
final videoControllerProvider = Provider<VideoController>((ref) {
  final datasource = ref.watch(videoPlayerDatasourceProvider);
  return VideoController(
    datasource.player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !Platform.isLinux,
    ),
  );
});

MaterialVideoControlsThemeData _buildMobileControlsTheme(
  MediaQueryData mq, {
  required List<Widget> topButtonBar,
  required List<Widget> bottomButtonBar,
}) {
  // Явно, а не через copyWith: у copyWith нет padding/bottomButtonBarMargin,
  // а молчаливое выпадение отступов хуже дублирования семи полей сикбара.
  const base = _seekBarBaseTheme;
  return MaterialVideoControlsThemeData(
    seekBarHeight: base.seekBarHeight,
    seekBarThumbSize: base.seekBarThumbSize,
    seekBarMargin: base.seekBarMargin,
    seekBarPositionColor: base.seekBarPositionColor,
    seekBarThumbColor: base.seekBarThumbColor,
    seekBarBufferColor: base.seekBarBufferColor,
    seekBarColor: base.seekBarColor,
    topButtonBar: topButtonBar,
    bottomButtonBar: bottomButtonBar,
    padding: EdgeInsets.only(
      left: 12,
      right: 12,
      top: mq.padding.top > 0 ? mq.padding.top + 8 : 12,
      bottom: 24 + mq.padding.bottom,
    ),
    bottomButtonBarMargin: EdgeInsets.only(
      left: 16,
      right: 8,
      bottom: mq.padding.bottom,
    ),
  );
}

/// Паузить ли видео при сносе панели (системный «назад»):
/// только своё играющее непоставленное видео. Чистая функция ради
/// тестируемости — сама панель требует нативный libmpv.
bool shouldPauseOnPanelDispose(PlaybackState playback, int mediaId) {
  return playback is PlaybackPlaying &&
      playback.type == MediaType.video &&
      playback.media.id == mediaId &&
      !playback.isPaused;
}

class VideoPlayerPanel extends ConsumerStatefulWidget {
  const new({
    required this.media,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onClose,
    super.key,
  });

  final Media media;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onClose;

  @override
  ConsumerState<VideoPlayerPanel> createState() => _VideoPlayerPanelState();
}

class _VideoPlayerPanelState extends ConsumerState<VideoPlayerPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.isFullscreen) {
      _setFullscreenChrome(true);
    }
    // Создаём VideoController сразу: нативная текстура должна
    // прикрепиться к плееру до старта open().
    ref.read(videoControllerProvider);
  }

  void _setFullscreenChrome(bool fullscreen) {
    // Только системный UI (immersive vs edge-to-edge): ориентации не
    // трогаем вовсе — приложение нигде не лочит portrait (ни манифест,
    // ни main), и выставление «всех ориентаций» было бы no-op'ом,
    // маскирующимся под восстановление состояния.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  @override
  void didUpdateWidget(VideoPlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFullscreen && !oldWidget.isFullscreen) {
      _setFullscreenChrome(true);
    } else if (!widget.isFullscreen && oldWidget.isFullscreen) {
      _setFullscreenChrome(false);
    }
  }

  // Видео продолжает играть в фоне осознанно (как аудио): автопаузы
  // при сворачивании нет. Звонок фоновое видео не прерывает (прерывания
  // дёргают напрямую audio-движок) — известное ограничение.
  @override
  void dispose() {
    if (widget.isFullscreen) {
      _setFullscreenChrome(false);
    }
    // Системный «назад» сносит роут мимо экранной кнопки (та ставит
    // на паузу сама): без этого видео играло бы в никуда, а новая
    // карточка подхватывала бы старый трек из синглтон-плеера.
    // Паузим только своё неподоставленное видео — фоновое аудио и чужой
    // трек не трогаем. Заодно сохраняется прогресс для resume.
    if (shouldPauseOnPanelDispose(
      ref.read(playbackCoordinatorProvider),
      widget.media.id,
    )) {
      unawaited(
        ref.read(playbackCoordinatorProvider.notifier).pause(),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      playbackCoordinatorProvider.select(playerViewFromPlaybackState),
    );

    // Resume overlay.
    final savedPosition = view.savedPosition;

    final isMobile = Platform.isAndroid || Platform.isIOS;
    final mobileTheme = _buildMobileControlsTheme(
      MediaQuery.of(context),
      topButtonBar: [_BackButton(onClose: widget.onClose)],
      bottomButtonBar: [
        if (showResumeControl(view.kind, view.type, savedPosition))
          _ResumeButton(savedPosition: savedPosition!),
        const Spacer(),
        const _SeekButton(direction: -1),
        const _SeekButton(direction: 1),
        const _SpeedButton(),
        const SizedBox(width: 16),
        const Spacer(),
        const MaterialPositionIndicator(),
        if (!widget.isFullscreen)
          _FullscreenButton(onTap: widget.onToggleFullscreen),
      ],
    );

    final desktopTheme = const MaterialDesktopVideoControlsThemeData().copyWith(
      topButtonBar: [_BackButton(onClose: widget.onClose)],
      bottomButtonBar: [
        if (showResumeControl(view.kind, view.type, savedPosition))
          _ResumeButton(savedPosition: savedPosition!),
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
        if (!widget.isFullscreen)
          _FullscreenButton(onTap: widget.onToggleFullscreen),
      ],
    );

    final body = MaterialVideoControlsTheme(
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
    );

    final posterOrBody = Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (view.kind != PlayerViewKind.playing) _Poster(media: widget.media),
      ],
    );

    if (widget.isFullscreen) {
      return ColoredBox(color: Colors.black, child: posterOrBody);
    }
    // Embedded: 16:9 until video dimensions are known.
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(color: Colors.black, child: posterOrBody),
    );
  }
}

/// Показывать ли кнопку resume в панели контролов: только для играющего
/// видео с сохранённой позицией. Живёт вместе с контролами (прячется
/// с ними) — вместо бывшего висящего оверлея с собственным таймером.
///
/// isPaused осознанно НЕ в сигнатуре: кнопка теперь делает seek+play,
/// поэтому на паузе работает корректно, а не «выглядит сломанной».
bool showResumeControl(
  PlayerViewKind kind,
  MediaType? type,
  Duration? savedPosition,
) {
  return kind == PlayerViewKind.playing &&
      type == MediaType.video &&
      savedPosition != null;
}

/// Кнопка «продолжить с …» в баре контролов.
///
/// Аккуратно с вёрсткой (был инцидент с прилипанием): отступы с обеих
/// сторон, ширина ужата с ellipsis — на узких экранах текст обрежется,
/// а не распрёт ряд и не налезет на соседей.
class _ResumeButton extends ConsumerWidget {
  const new({required this.savedPosition});

  final Duration savedPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          // «Продолжить» обязано играть: один seek без play на паузе
          // выглядел бы как «кнопка не сработала». Ошибки глушим в лог:
          // необработанный async-гэп из кнопки роняет зону.
          onPressed: () async {
            final coordinator = ref.read(
              playbackCoordinatorProvider.notifier,
            );
            try {
              await coordinator.seekToSavedPosition();
              await coordinator.resume();
            } catch (e) {
              AppLogger.error('Resume from saved position failed', e);
            }
          },
          icon: const Icon(Icons.history, size: 20),
          label: Text(
            l.continueFrom(savedPosition.formatted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _Poster extends ConsumerWidget {
  const new({required this.media});
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(baseUrlProvider);
    final url = buildMediaImageUrl(
      baseUrl: baseUrl,
      mediaId: media.id,
      kind: MediaImageKind.thumb,
      cacheBust: media.updatedAt?.millisecondsSinceEpoch,
    );
    return IgnorePointer(
      child: AuthNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _BackButton extends ConsumerWidget {
  const new({this.onClose});
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      color: Colors.white,
      icon: const Icon(Icons.arrow_back),
      onPressed: () async {
        await ref.read(playbackCoordinatorProvider.notifier).pause();
        final cb = onClose;
        if (cb != null) {
          cb();
        } else {
          if (context.mounted) await Navigator.of(context).maybePop();
        }
      },
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  const new({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Colors.white,
      icon: const Icon(Icons.fullscreen),
      onPressed: onTap,
    );
  }
}

class _SeekButton extends ConsumerWidget {
  const new({required this.direction});
  final int direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.read(playbackCoordinatorProvider.notifier);
    return IconButton(
      color: Colors.white,
      icon: Icon(direction < 0 ? Icons.replay_10 : Icons.forward_10),
      iconSize: 24,
      onPressed: () {
        final video = ref.read(videoPlayerDatasourceProvider);
        final target = clampSeekPosition(
          position: video.position,
          step: _seekStep * direction,
          duration: video.duration,
        );
        unawaited(coordinator.seek(target));
      },
    );
  }
}

class _SpeedButton extends ConsumerStatefulWidget {
  const new();

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
    unawaited(_rateSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Colors.white,
      icon: Text(
        '${_rate}x',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      onPressed: () {
        final next = _rate >= _maxSpeed ? _minSpeed : _rate + _speedStep;
        unawaited(
          ref.read(playbackCoordinatorProvider.notifier).setSpeed(next),
        );
      },
    );
  }
}

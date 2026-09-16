import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_image_url.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_view.dart';
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

class _VideoPlayerPanelState extends ConsumerState<VideoPlayerPanel>
    with WidgetsBindingObserver {
  /// В fullscreen: показываем resume-оверлей над контролами.
  bool _showResumeButton = false;
  Timer? _resumeTimer;
  static const _resumeHideDelay = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isFullscreen) {
      _enterFullscreenChrome();
    }
    // Создаём VideoController сразу: нативная текстура должна
    // прикрепиться к плееру до старта open().
    ref.read(videoControllerProvider);
  }

  void _enterFullscreenChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreenChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void didUpdateWidget(VideoPlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFullscreen && !oldWidget.isFullscreen) {
      _enterFullscreenChrome();
    } else if (!widget.isFullscreen && oldWidget.isFullscreen) {
      _exitFullscreenChrome();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final playback = ref.read(playbackCoordinatorProvider);
    if (playback is PlaybackPlaying &&
        playback.type == MediaType.video &&
        !playback.isPaused) {
      unawaited(ref.read(playbackCoordinatorProvider.notifier).pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    if (widget.isFullscreen) {
      _exitFullscreenChrome();
    }
    super.dispose();
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
    unawaited(
      ref.read(playbackCoordinatorProvider.notifier).seekToSavedPosition(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final view = ref.watch(
      playbackCoordinatorProvider.select(playerViewFromPlaybackState),
    );

    // Resume overlay.
    if (view.kind == PlayerViewKind.playing &&
        view.type == MediaType.video &&
        view.savedPosition != null &&
        !_showResumeButton &&
        _resumeTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResumeOverlay(view.savedPosition!);
      });
    }

    final isMobile = Platform.isAndroid || Platform.isIOS;
    final mobileTheme = _buildMobileControlsTheme(
      MediaQuery.of(context),
      topButtonBar: [_BackButton(onClose: widget.onClose)],
      bottomButtonBar: [
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
        if (_showResumeButton && view.savedPosition != null)
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
                        border: Border.all(color: Colors.white24),
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
                            l.continueFrom(view.savedPosition!.formatted),
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
        final position = ref.read(videoPlayerDatasourceProvider).position;
        coordinator.seek(
          position + Duration(seconds: _seekStep.inSeconds * direction),
        );
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
    _rateSub?.cancel();
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
        ref.read(playbackCoordinatorProvider.notifier).setSpeed(next);
      },
    );
  }
}

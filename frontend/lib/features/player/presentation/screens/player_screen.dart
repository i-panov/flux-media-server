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

final videoControllerProvider = Provider.autoDispose<VideoController>((ref) {
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
  seekBarThumbSize: 16,
  seekBarMargin: EdgeInsets.only(left: 12, right: 12),
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 24),
  seekBarPositionColor: Colors.deepPurple,
  seekBarThumbColor: Colors.deepPurple,
  seekBarBufferColor: Color(0x66FFFFFF),
  seekBarColor: Color(0x33FFFFFF),
);

@RoutePage()
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.media, super.key});

  final Media media;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlaybackCoordinator _coordinator;

  /// Shows a semi-transparent "resume" button when a saved position exists.
  bool _showResumeButton = false;
  Timer? _resumeTimer;

  /// Auto-hide delay for the resume button.
  static const _resumeHideDelay = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(playbackCoordinatorProvider.notifier);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Allow all orientations — video aspect ratio determines the best fit.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use setQueue so the queue is in sync with what's playing.
      // Without this, _onCompleted would jump to a stale queue item.
      ref.read(playQueueProvider.notifier).setQueue([widget.media]);
    });
  }

  void _showResumeOverlay(Duration savedPosition) {
    _resumeTimer?.cancel();
    setState(() => _showResumeButton = true);
    _resumeTimer = Timer(_resumeHideDelay, () {
      if (mounted) setState(() => _showResumeButton = false);
    });
  }

  void _onResumeTap() {
    _resumeTimer?.cancel();
    setState(() => _showResumeButton = false);
    _coordinator.seekToSavedPosition();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    // Stop playback (also persists watch progress) when leaving the screen,
    // e.g. via system back button which bypasses the in-app back button.
    _coordinator.stop();
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
    final state = ref.watch(playbackCoordinatorProvider);
    final videoController = ref.watch(videoControllerProvider);

    // Show resume button once when savedPosition is set.
    if (state is PlaybackPlaying &&
        state.type == MediaType.video.value &&
        state.savedPosition != null &&
        !_showResumeButton &&
        _resumeTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showResumeOverlay(state.savedPosition!);
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: state.when(
        initial: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        playing:
            (media, type, isPaused, position, duration, speed, savedPosition) {
          if (type != 'video') {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          // Build controls theme with custom buttons (back, ±10s, speed)
          // integrated into media_kit's button bars. This avoids a
          // full-screen GestureDetector that would intercept taps meant
          // for the built-in play/pause button.
          final isMobile = Platform.isAndroid || Platform.isIOS;

          final player = ref.read(videoPlayerDatasourceProvider).player;

          final backBtn = IconButton(
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            tooltip: l.mediaDetail,
            onPressed: () async {
              await player.pause();
              if (context.mounted) await context.maybePop();
            },
          );

          final seekBackBtn = IconButton(
            color: Colors.white,
            icon: const Icon(Icons.replay_10),
            iconSize: 24,
            tooltip: '-10s',
            onPressed: () {
              // Read the position directly from the player: the value in
              // PlaybackState is updated via a stream and can lag behind,
              // making consecutive taps seek from a stale position.
              _coordinator.seek(
                player.state.position - const Duration(seconds: 10),
              );
            },
          );

          final seekFwdBtn = IconButton(
            color: Colors.white,
            icon: const Icon(Icons.forward_10),
            iconSize: 24,
            tooltip: '+10s',
            onPressed: () {
              _coordinator.seek(
                player.state.position + const Duration(seconds: 10),
              );
            },
          );

          // Speed button uses StreamBuilder on player.stream.rate so the
          // label updates immediately when the rate changes — media_kit
          // controls don't rebuild when the theme data changes, so a
          // plain Text('${speed}x') would stay stale.
          Widget buildSpeedBtn() => StreamBuilder<double>(
                stream: player.stream.rate,
                initialData: player.state.rate,
                builder: (context, snapshot) {
                  final rate = snapshot.data ?? 1.0;
                  return IconButton(
                    color: Colors.white,
                    icon: Text(
                      '${rate}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    tooltip: l.speed,
                    onPressed: () {
                      final next = rate >= 2.0 ? 0.5 : rate + 0.5;
                      _coordinator.setSpeed(next);
                    },
                  );
                },
              );

          final mobileTheme = _seekBarTheme.copyWith(
            // Back button stays in the top bar.
            topButtonBar: [backBtn],
            // ±10s + speed in the bottom bar, centered via Spacers so they
            // don't stick to the left edge and cover the seek bar.
            bottomButtonBar: [
              const Spacer(),
              seekBackBtn,
              seekFwdBtn,
              buildSpeedBtn(),
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
            topButtonBar: [backBtn],
            bottomButtonBar: [
              const MaterialDesktopSkipPreviousButton(),
              const MaterialDesktopPlayOrPauseButton(),
              const MaterialDesktopSkipNextButton(),
              const MaterialDesktopVolumeButton(),
              seekBackBtn,
              seekFwdBtn,
              buildSpeedBtn(),
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
                      controller: videoController,
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
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        error: (message) => Center(
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
            ],
          ),
        ),
        completed: () => Stack(
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
                          .setQueue([widget.media]);
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
        ),
      ),
    );
  }
}

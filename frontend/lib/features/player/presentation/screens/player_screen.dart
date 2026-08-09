import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
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

@RoutePage()
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.media, super.key});

  final Media media;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _resumeDialogShown = false;
  late final PlaybackCoordinator _coordinator;

  /// Visibility of custom overlay controls (back button, seek ±10s, speed).
  bool _overlayVisible = true;
  Timer? _hideTimer;

  /// Auto-hide delay — matches MaterialVideoControls default (3s).
  static const _hideDelay = Duration(seconds: 3);

  void _showOverlay() {
    _hideTimer?.cancel();
    setState(() => _overlayVisible = true);
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _toggleOverlay() {
    if (_overlayVisible) {
      _hideTimer?.cancel();
      setState(() => _overlayVisible = false);
    } else {
      _showOverlay();
    }
  }

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
      _showOverlay();
    });
  }

  void _showResumeDialog(Duration savedPosition) {
    final l = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.continueWatching),
        content: Text(l.continueFrom(savedPosition.formatted)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _coordinator.startFromBeginning();
            },
            child: Text(l.startFromBeginning),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _coordinator.seekToSavedPosition();
            },
            child: Text(l.play),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
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

    // Show resume dialog once when savedPosition is set.
    if (state is PlaybackPlaying &&
        state.type == MediaType.video.value &&
        state.savedPosition != null &&
        !_resumeDialogShown) {
      _resumeDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showResumeDialog(state.savedPosition!);
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
          return Stack(
            children: [
              Positioned.fill(
                child: Video(
                  controller: videoController,
                  controls: Platform.isAndroid || Platform.isIOS
                      ? MaterialVideoControls
                      : MaterialDesktopVideoControls,
                ),
              ),
              // Transparent tap catcher — toggles overlay visibility.
              // translucent allows MaterialVideoControls underneath to also
              // receive the tap so its own controls stay in sync.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleOverlay,
                ),
              ),
              AnimatedOpacity(
                opacity: _overlayVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_overlayVisible,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 8,
                        child: IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.arrow_back),
                          tooltip: l.mediaDetail,
                          onPressed: () async {
                            await ref
                                .read(videoPlayerDatasourceProvider)
                                .player
                                .pause();
                            if (context.mounted) await context.maybePop();
                          },
                        ),
                      ),
                      Positioned(
                        bottom: 80,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ControlButton(
                              icon: Icons.replay_10,
                              tooltip: '-10s',
                              onPressed: () {
                                final newPos =
                                    position - const Duration(seconds: 10);
                                _coordinator.seek(newPos);
                                _showOverlay();
                              },
                            ),
                            const SizedBox(width: 16),
                            _ControlButton(
                              icon: Icons.forward_10,
                              tooltip: '+10s',
                              onPressed: () {
                                final newPos =
                                    position + const Duration(seconds: 10);
                                _coordinator.seek(newPos);
                                _showOverlay();
                              },
                            ),
                            const SizedBox(width: 24),
                            _ControlButton(
                              label: '${speed}x',
                              tooltip: l.speed,
                              onPressed: () {
                                final next = speed >= 2.0 ? 0.5 : speed + 0.5;
                                _coordinator.setSpeed(next);
                                _showOverlay();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.onPressed,
    this.icon,
    this.label,
    this.tooltip,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 28)
                : Text(
                    label ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
          ),
        ),
      ),
    );
  }
}

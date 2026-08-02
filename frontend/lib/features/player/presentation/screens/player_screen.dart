import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/platform_detection.dart';
import 'package:flux_media_server/shared/models/media.dart';

final videoControllerProvider = Provider.autoDispose<VideoController>((ref) {
  final datasource = ref.watch(videoPlayerDatasourceProvider);
  return VideoController(
    datasource.player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !isRunningInWSL,
    ),
  );
});

@RoutePage()
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.media});

  final Media media;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _resumeDialogShown = false;
  late final PlaybackCoordinator _coordinator;

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
      _coordinator.play(widget.media);
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
        state.type == 'video' &&
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
        playing: (media, type, isPaused, position, duration, speed, savedPosition) {
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
                  controls: MaterialDesktopVideoControls,
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: l.mediaDetail,
                  onPressed: () async {
                    await ref.read(videoPlayerDatasourceProvider).player.pause();
                    if (context.mounted) context.maybePop();
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
                        final newPos = position - const Duration(seconds: 10);
                        _coordinator.seek(newPos);
                      },
                    ),
                    const SizedBox(width: 16),
                    _ControlButton(
                      icon: Icons.forward_10,
                      tooltip: '+10s',
                      onPressed: () {
                        final newPos = position + const Duration(seconds: 10);
                        _coordinator.seek(newPos);
                      },
                    ),
                    const SizedBox(width: 24),
                    _ControlButton(
                      label: '${speed}x',
                      tooltip: l.speed,
                      onPressed: () {
                        final next = speed >= 2.0 ? 0.5 : speed + 0.5;
                        _coordinator.setSpeed(next);
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
                      _coordinator.reset();
                      _coordinator.play(widget.media);
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
    this.icon,
    this.label,
    this.tooltip,
    required this.onPressed,
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

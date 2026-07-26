import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flux_media_server/features/player/presentation/providers/player_provider.dart';
import 'package:flux_media_server/core/utils/platform_detection.dart';
import 'package:flux_media_server/features/player/presentation/widgets/pip_manager.dart';
import 'package:flux_media_server/shared/models/media.dart';

final videoControllerProvider = Provider<VideoController>((ref) {
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
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerProvider.notifier).play(widget.media);
    });
  }

  @override
  void dispose() {
    if (PipManager.isActive) {
      PipManager.exitPip();
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
    final state = ref.watch(playerProvider);
    final videoController = ref.watch(videoControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: state.when(
        initial: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        playing: (media, isPaused, position, duration) {
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
                  onPressed: () async {
                    await ref.read(videoPlayerDatasourceProvider).player.pause();
                    if (context.mounted) context.maybePop();
                  },
                ),
              ),
            ],
          );
        },
        completed: () => Center(
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
                  ref.read(playerProvider.notifier).reset();
                  ref.read(playerProvider.notifier).play(widget.media);
                },
                child: Text(l.replay),
              ),
            ],
          ),
        ),
        error: (message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(playerProvider.notifier).reset();
                  ref.read(playerProvider.notifier).play(widget.media);
                },
                child: Text(l.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

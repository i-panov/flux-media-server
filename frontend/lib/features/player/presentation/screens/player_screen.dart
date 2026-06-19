import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flux_media_server/features/player/presentation/providers/player_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

final videoControllerProvider = Provider<VideoController>((ref) {
  final datasource = ref.watch(videoPlayerDatasourceProvider);
  return VideoController(datasource.player);
});

@RoutePage()
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.media});

  final Media media;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showControls = true;
  bool _isDragging = false;
  double _dragPosition = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    ref.read(playerProvider.notifier).play(widget.media);
  }

  @override
  void dispose() {
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
    final state = ref.watch(playerProvider);
    final videoController = ref.watch(videoControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: state.when(
        initial: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        playing: (media, isPaused, position, duration) {
          final sliderValue = _isDragging
              ? _dragPosition
              : position.inSeconds.toDouble().clamp(
                  0.0, (duration ?? position).inSeconds.toDouble());
          final sliderMax =
              (duration ?? position).inSeconds.toDouble().clamp(1.0, double.infinity);

          return Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Video(controller: videoController),
              ),
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value: sliderValue,
                          max: sliderMax,
                          onChangeStart: (_) => setState(() => _isDragging = true),
                          onChanged: (value) => setState(() => _dragPosition = value),
                          onChangeEnd: (value) {
                            setState(() => _isDragging = false);
                            ref
                                .read(playerProvider.notifier)
                                .seek(Duration(seconds: value.toInt()));
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              position.formatted,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              iconSize: 48,
                              color: Colors.white,
                              icon: Icon(
                                isPaused ? Icons.play_arrow : Icons.pause,
                              ),
                              onPressed: () {
                                if (isPaused) {
                                  ref.read(playerProvider.notifier).resume();
                                } else {
                                  ref.read(playerProvider.notifier).pause();
                                }
                              },
                            ),
                            const SizedBox(width: 16),
                            Text(
                              duration != null ? duration.formatted : '--:--',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
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
              const Text(
                'Playback completed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(playerProvider.notifier).reset();
                  ref.read(playerProvider.notifier).play(widget.media);
                },
                child: const Text('Replay'),
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
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_detail.dart';
import 'package:flux_media_server/shared/models/media.dart';

final mediaDetailProvider =
    StateNotifierProvider.autoDispose<MediaDetailNotifier, MediaDetailState>(
  (ref) => MediaDetailNotifier(getMediaDetail: ref.watch(getMediaDetailUseCase)),
);

final getMediaDetailUseCase = Provider<GetMediaDetail>((ref) {
  throw UnimplementedError(
    'getMediaDetailUseCase must be overridden at app level',
  );
});

@RoutePage()
class MediaDetailScreen extends ConsumerStatefulWidget {
  const MediaDetailScreen({super.key, required this.mediaId});

  final int mediaId;

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(mediaDetailProvider.notifier).load(widget.mediaId);
  }

  String _thumbnailUrl() {
    return 'http://localhost:8080/api/media/${widget.mediaId}/thumb';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mediaDetailProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Media Detail')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (media) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CachedNetworkImage(
                imageUrl: _thumbnailUrl(),
                fit: BoxFit.cover,
                height: 300,
                placeholder: (_, __) => const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const SizedBox(
                  height: 300,
                  child: Center(child: Icon(Icons.broken_image, size: 64)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${media.year} · ${media.type}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                    if (media.description != null) ...[
                      const SizedBox(height: 16),
                      Text(media.description!),
                    ],
                    if (media.duration != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Duration: ${Duration(seconds: media.duration!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          // TODO: implement playback
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        error: (message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(mediaDetailProvider.notifier).load(widget.mediaId),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/features/media/presentation/screens/media_detail_screen.dart';

class MediaListScreen extends ConsumerStatefulWidget {
  const MediaListScreen({super.key});

  @override
  ConsumerState<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends ConsumerState<MediaListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(mediaListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mediaListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Media Library')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (items, total, hasReachedMax) => RefreshIndicator(
          onRefresh: () => ref.read(mediaListProvider.notifier).load(),
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length + (hasReachedMax ? 0 : 1),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final media = items[index];
              return MediaCard(
                media: media,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaDetailScreen(mediaId: media.id),
                    ),
                  );
                },
              );
            },
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
                    ref.read(mediaListProvider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final mediaListProvider =
    StateNotifierProvider<MediaListNotifier, MediaListState>((ref) {
  throw UnimplementedError(
    'mediaListProvider must be overridden at app level',
  );
});

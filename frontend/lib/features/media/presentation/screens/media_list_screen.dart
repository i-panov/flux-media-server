import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';

@RoutePage()
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
        data: (result) {
          final hasReachedMax = result.items.length >= result.total;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(mediaListProvider.future),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = (constraints.maxWidth / 180).floor().clamp(2, 6);
                return GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: result.items.length + (hasReachedMax ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index == result.items.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final media = result.items[index];
                    return MediaCard(
                      media: media,
                      onTap: () {
                        context.router.push(MediaDetailRoute(mediaId: media.id));
                      },
                    );
                  },
                );
              },
            ),
          );
        },
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(mediaListProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

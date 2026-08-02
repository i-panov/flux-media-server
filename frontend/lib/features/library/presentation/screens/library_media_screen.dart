import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_media_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/library.dart';

@RoutePage()
class LibraryMediaScreen extends ConsumerStatefulWidget {
  const LibraryMediaScreen({super.key, required this.library});

  final MediaLibrary library;

  @override
  ConsumerState<LibraryMediaScreen> createState() => _LibraryMediaScreenState();
}

class _LibraryMediaScreenState extends ConsumerState<LibraryMediaScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      ref.read(libraryMediaProvider(widget.library).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mediaState = ref.watch(libraryMediaProvider(widget.library));
    final typeFilter = ref.watch(libraryMediaTypeFilterProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.library.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchBar(
              controller: _searchController,
              hintText: l.searchMedia,
              leading: const Icon(Icons.search),
              onChanged: (value) {
                if (value.isEmpty) {
                  ref.read(libraryMediaTypeFilterProvider.notifier).state = null;
                }
              },
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  ref.read(libraryMediaTypeFilterProvider.notifier).state = value;
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(l.all),
                  selected: typeFilter == null,
                  onSelected: (_) => ref.read(libraryMediaTypeFilterProvider.notifier).state = null,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(l.video),
                  selected: typeFilter == 'video',
                  onSelected: (_) => ref.read(libraryMediaTypeFilterProvider.notifier).state = 'video',
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(l.audio),
                  selected: typeFilter == 'audio',
                  onSelected: (_) => ref.read(libraryMediaTypeFilterProvider.notifier).state = 'audio',
                ),
              ],
            ),
          ),
          Expanded(
            child: mediaState.when(
              loading: () => _buildSkeletonGrid(context),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(e.toString()),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(libraryMediaProvider(widget.library)),
                      child: Text(l.retry),
                    ),
                  ],
                ),
              ),
              data: (media) {
                if (media.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(l.noMediaFound),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(libraryMediaProvider(widget.library));
                    await ref.watch(libraryMediaProvider(widget.library).future);
                  },
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(2, 6),
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: media.length,
                    itemBuilder: (context, index) {
                      final item = media[index];
                      return MediaCard(
                        media: item,
                        onTap: () => context.router.push(MediaDetailRoute(mediaId: item.id)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonGrid(BuildContext context) {
    final crossAxisCount = (MediaQuery.of(context).size.width / 180).floor().clamp(2, 6);
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: crossAxisCount * 2,
      itemBuilder: (context, index) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SkeletonWidget(width: double.infinity, height: double.infinity),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonWidget(height: 14, width: double.infinity),
                  const SizedBox(height: 6),
                  const SkeletonWidget(height: 10, width: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

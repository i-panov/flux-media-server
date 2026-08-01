import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final downloadsState = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        title: Text(l.downloads),
      ),
      body: downloadsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(downloadsProvider),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
        data: (mediaList) {
          if (mediaList.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l.noMediaFound),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(2, 6),
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: mediaList.length,
            itemBuilder: (context, index) {
              final media = mediaList[index];
              return MediaCard(
                media: media,
                onTap: () => context.router.push(MediaDetailRoute(mediaId: media.id)),
                isFavorite: false,
                onFavorite: null,
                isDownloaded: true,
                onDownload: () async {
                  await ref.read(offlineCacheServiceProvider).remove(media.id);
                  ref.invalidate(downloadsProvider);
                },
              );
            },
          );
        },
      ),
    );
  }
}

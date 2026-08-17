import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_actions.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_details_panel.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_player_panel.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class VideoDetailScreen extends ConsumerStatefulWidget {
  const VideoDetailScreen({required this.mediaId, super.key});

  final int mediaId;

  @override
  ConsumerState<VideoDetailScreen> createState() =>
      _VideoDetailScreenState();
}

class _VideoDetailScreenState
    extends ConsumerState<VideoDetailScreen> {
  bool _isFullscreen = false;
  bool _isUploadingCover = false;
  bool _coverUploadCancelled = false;

  void _setFullscreen(bool value) {
    setState(() => _isFullscreen = value);
  }

  Future<void> _toggleFavorite() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    if (media == null) return;
    await ref
        .read(favoriteToggleProvider(media.id).notifier)
        .toggle();
  }

  Future<void> _addToCollection() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    final type = media?.type.value ?? 'video';
    await showAddToCollectionDialog(
      context,
      widget.mediaId,
      mediaType: type,
    );
  }

  Future<void> _changeCover() async {
    if (_isUploadingCover) {
      setState(() => _coverUploadCancelled = true);
      return;
    }
    await changeMediaCover(
      context,
      ref,
      widget.mediaId,
      isCancelled: () => _coverUploadCancelled,
      onUploadStarted: () {
        if (mounted) {
          setState(() {
            _isUploadingCover = true;
            _coverUploadCancelled = false;
          });
        }
      },
      onUploadFinished: () {
        if (mounted) {
          setState(() {
            _isUploadingCover = false;
            _coverUploadCancelled = false;
          });
        }
      },
    );
  }

  Future<void> _download() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    if (media == null) return;

    final downloadState = ref.read(downloadNotifierProvider(widget.mediaId));

    if (downloadState is DownloadDownloaded) {
      await ref
          .read(downloadNotifierProvider(widget.mediaId).notifier)
          .remove(widget.mediaId);
    } else if (downloadState is DownloadDownloading) {
      await ref
          .read(downloadNotifierProvider(widget.mediaId).notifier)
          .cancel(widget.mediaId);
    } else {
      await ref
          .read(downloadNotifierProvider(widget.mediaId).notifier)
          .download(media);

      if (!mounted) return;
      final newState = ref.read(downloadNotifierProvider(widget.mediaId));
      if (newState is DownloadError) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.errorLabel}: ${newState.message}'),
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    await deleteMediaWithConfirm(
      context,
      ref,
      widget.mediaId,
      popOnSuccess: true,
    );
  }

  Future<void> _play() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    if (media == null) return;
    ref.read(playQueueProvider.notifier).setQueue([media]);
    await ref
        .read(playbackCoordinatorProvider.notifier)
        .play(media);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaDetailProvider(widget.mediaId));

    return state.maybeWhen(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (message) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(mediaDetailProvider(widget.mediaId).notifier)
                    .load(widget.mediaId),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
      ),
      loaded: (media) => _buildLoaded(l, media),
      orElse: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildLoaded(AppLocalizations l, Media media) {
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: VideoPlayerPanel(
                media: media,
                isFullscreen: true,
                onClose: () => _setFullscreen(false),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          color: Colors.white,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.maybePop(),
        ),
        actions: [
          IconButton(
            color: Colors.white,
            icon: _isUploadingCover
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.image),
            tooltip: _isUploadingCover
                ? l.uploadingCover
                : l.changeCover,
            onPressed: _changeCover,
          ),
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.edit),
            onPressed: () => showEditMetadataDialog(
              context,
              ref,
              media,
            ),
            tooltip: l.edit,
          ),
          IconButton(
            color: Colors.red,
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
            tooltip: l.delete,
          ),
        ],
      ),
      body: Column(
        children: [
          VideoPlayerPanel(
            media: media,
            isFullscreen: false,
            onToggleFullscreen: () => _setFullscreen(true),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: VideoDetailsPanel(
                media: media,
                onPlay: _play,
                onToggleFavorite: _toggleFavorite,
                onAddToCollection: _addToCollection,
                onDownload: _download,
                onChangeCover: _changeCover,
                onEditMetadata: () => showEditMetadataDialog(
                  context,
                  ref,
                  media,
                ),
                onDelete: _delete,
                onAddToQueue: () async {
                  ref
                      .read(playQueueProvider.notifier)
                      .enqueue(media);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

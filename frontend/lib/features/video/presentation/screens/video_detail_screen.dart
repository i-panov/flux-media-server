import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/extract_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_actions.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/offline/presentation/widgets/save_to_files.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/video/presentation/providers/extracted_audio_provider.dart';
import 'package:flux_media_server/features/video/presentation/utils/extract_audio_flow.dart';
import 'package:flux_media_server/features/video/presentation/utils/video_wakelock.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_details_panel.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_player_panel.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class VideoDetailScreen extends ConsumerStatefulWidget {
  const new({required this.mediaId, super.key});

  final int mediaId;

  @override
  ConsumerState<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends ConsumerState<VideoDetailScreen> {
  bool _isFullscreen = false;
  bool _isUploadingCover = false;
  bool _coverUploadCancelled = false;

  /// Последнее известное состояние плеера: решение о паузе принимается
  /// по нему, а не чтением провайдера в dispose.
  PlaybackState _lastPlayback = const PlaybackState.initial();

  /// Координатор захвачен заранее: в dispose обращаться к `ref` нельзя —
  /// виджет демонтируется, и чтение бросает «Using ref when a widget is
  /// about to or has been unmounted is unsafe». Из-за этого пауза при
  /// уходе с экрана не срабатывала, и видео играло в фоне.
  late final PlaybackCoordinator _coordinator;

  /// Экран не должен гаснуть, пока видео играет на переднем плане.
  ///
  /// Управление вынесено из media_kit_video: там wakelock привязан к
  /// потоку `playing` и о lifecycle приложения не знает — в свёрнутом
  /// состоянии флаг оставался включённым и не давал устройству уснуть.
  /// Здесь видно оба условия: играет ли видео и на переднем ли плане
  /// приложение.
  late final VideoWakelock _wakelock;

  /// Lifecycle приложения: по нему снимается wakelock при уходе в фон.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(playbackCoordinatorProvider.notifier);
    _wakelock = VideoWakelock();
    // Скрытие и пауза означают «приложение в фоне» (на десктопе —
    // свёрнутое окно), возврат и показ — «снова на экране». Промежуточное
    // состояние inactive (шторка уведомлений, входящий звонок) игнорируем:
    // приложение ещё видно, и экран должен гореть.
    _lifecycle = AppLifecycleListener(
      onHide: () => _wakelock.updateForeground(foreground: false),
      onPause: () => _wakelock.updateForeground(foreground: false),
      onShow: () => _wakelock.updateForeground(foreground: true),
      onResume: () => _wakelock.updateForeground(foreground: true),
    );
    // Состояние плеера запоминается подпиской, а читается из кэша —
    // по той же причине, что и координатор.
    ref.listenManual(playbackCoordinatorProvider, (_, next) {
      _lastPlayback = next;
      _wakelock.updatePlaying(
        playing: isVideoPlayingOnScreen(next, widget.mediaId),
      );
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    // Пауза при УХОДЕ с экрана. Раньше это делала панель в своём dispose,
    // но её dispose срабатывает и при смене режима (встроенная ⇄ полный
    // экран): экран собирает другую ветвь дерева, и панель
    // пересоздаётся. Из-за этого вход в полный экран ставил видео на
    // паузу — пользователь видел застывший кадр.
    //
    // Здесь различие видно явно: dispose экрана — это именно уход
    // (системный «назад» сносит роут мимо экранной кнопки), а смена
    // режима экран не трогает.
    //
    // Паузим только своё неподоставленное видео — фоновое аудио и чужой
    // трек не трогаем. Заодно сохраняется прогресс для resume.
    if (shouldPauseOnScreenDispose(_lastPlayback, widget.mediaId)) {
      unawaited(_coordinator.pause());
    }
    // Экран уходит — флаг «не гасить экран» больше не нужен.
    _lifecycle.dispose();
    _wakelock.dispose();
    super.dispose();
  }

  void _setFullscreen(bool value) {
    setState(() => _isFullscreen = value);
  }

  Future<void> _toggleFavorite() async {
    final media = ref
        .read(mediaDetailProvider(widget.mediaId))
        .maybeWhen(loaded: (m) => m, orElse: () => null);
    if (media == null) return;
    await ref.read(favoriteToggleProvider(media.id).notifier).toggle();
  }

  Future<void> _addToCollection() async {
    final media = ref
        .read(mediaDetailProvider(widget.mediaId))
        .maybeWhen(loaded: (m) => m, orElse: () => null);
    final type = media?.type.value ?? 'video';
    await showAddToCollectionDialog(context, widget.mediaId, mediaType: type);
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
    final media = ref
        .read(mediaDetailProvider(widget.mediaId))
        .maybeWhen(loaded: (m) => m, orElse: () => null);
    if (media == null) return;

    final downloads = ref.read(downloadsStateProvider.notifier);
    final downloadState = downloads.stateOf(widget.mediaId);

    if (downloadState is DownloadDownloaded) {
      await downloads.remove(widget.mediaId);
    } else if (downloadState is DownloadDownloading) {
      await downloads.cancel(widget.mediaId);
    } else {
      await downloads.download(media);

      if (!mounted) return;
      final newState = downloads.stateOf(widget.mediaId);
      if (newState is DownloadError) {
        showErrorSnackBar(context, newState.message);
      }
    }
  }

  Future<void> _saveToFiles(Media media) async {
    if (!mounted) return;
    await saveMediaToFiles(context, ref, media);
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
    final media = ref
        .read(mediaDetailProvider(widget.mediaId))
        .maybeWhen(loaded: (m) => m, orElse: () => null);
    if (media == null) return;
    // setQueue сам открывает очередь в плеере и запускает первый трек.
    await ref.read(playQueueProvider.notifier).setQueue([media]);
  }

  /// Извлечение аудио: флоу в extract_audio_flow (тестируем отдельно —
  /// экрану остаются только колбэки панели).
  Future<void> _extractAudio() async {
    await runExtractAudioFlow(ref, context, widget.mediaId);
  }

  /// Отмена летящего джоба из кнопки-переключателя панели.
  Future<void> _cancelExtract() async {
    ref.read(extractControllerProvider.notifier).cancel();
  }

  /// Переход к уже извлечённому треку: в очередь и играть (как _play),
  /// затем назад к списку — там виден мини-плеер с управлением.
  /// На вкладку «Аудио» не прыгаем: уважаем контекст браузинга.
  /// Координатор от экрана не зависит, dispose-проверка аудио не тронет.
  Future<void> _openExtractedAudio(Media track) async {
    unawaited(ref.read(playQueueProvider.notifier).setQueue([track]));
    if (mounted) await context.router.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaDetailProvider(widget.mediaId));

    return state.maybeWhen(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
      orElse: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }

  Widget _buildLoaded(AppLocalizations l, Media media) {
    // Связка с извлечённым треком — развилкой, а не .value: loading
    // блокирует кнопку (нельзя решать вслепую), error оставляет кнопку
    // (тап ретраит чтение + сервер перепроверяет в POST).
    final extractedAsync = ref.watch(extractedAudioProvider(widget.mediaId));
    final extractedTrack = extractedAsync.maybeWhen(
      data: (m) => m,
      orElse: () => null,
    );
    final isExtracting = ref.watch(
      extractControllerProvider.select((s) => s.isExtracting),
    );
    if (_isFullscreen) {
      return PopScope(
        // Системная «назад» в полном экране сворачивает видео в карточку,
        // а не уходит с экрана: иначе выход из полного экрана был бы
        // неочевиден (кнопка в углу автоскрывается вместе с остальными
        // контролами), а «назад» сразу закрывал бы экран вместе с
        // видео.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _setFullscreen(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: VideoPlayerPanel(
                  media: media,
                  isFullscreen: true,
                  // Кнопка полного экрана в углу сворачивает видео обратно
                  // в карточку: отдельной стрелки «назад» нет.
                  onToggleFullscreen: () => _setFullscreen(false),
                ),
              ),
            ],
          ),
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
          // Только pop, без паузы: она происходит в dispose ЭКРАНА
          // (shouldPauseOnScreenDispose) — там видно различие между
          // «уход с экрана» и «смена режима». Если гвард тронут здесь,
          // встроенный «назад» снова начнёт играть в никуда.
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.maybePop(),
        ),
        // Действий в AppBar больше нет: смена обложки, правка и удаление
        // живут в общем вертикальном списке панели — там у всех одна
        // форма (иконка + подпись), а не «три иконки без подписей».
      ),
      body: Column(
        children: [
          VideoPlayerPanel(
            media: media,
            onPlay: _play,
            onToggleFullscreen: () => _setFullscreen(true),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: VideoDetailsPanel(
                media: media,
                onToggleFavorite: _toggleFavorite,
                onAddToCollection: _addToCollection,
                onDownload: _download,
                onSaveToFiles: () async {
                  final media = ref
                      .read(mediaDetailProvider(widget.mediaId))
                      .maybeWhen(loaded: (m) => m, orElse: () => null);
                  if (media == null) return;
                  await _saveToFiles(media);
                },
                onExtractAudio: _extractAudio,
                onCancelExtract: _cancelExtract,
                onOpenExtractedAudio: extractedTrack != null
                    ? () => _openExtractedAudio(extractedTrack)
                    : null,
                isExtracting: isExtracting,
                isUploadingCover: _isUploadingCover,
                linkLoading: extractedAsync.isLoading,
                onChangeCover: _changeCover,
                onEditMetadata: () =>
                    showEditMetadataDialog(context, ref, media),
                onDelete: _delete,
                onAddToQueue: () async {
                  ref.read(playQueueProvider.notifier).enqueue(media);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

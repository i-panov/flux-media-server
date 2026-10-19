import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/media_image_url.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_view.dart';
import 'package:flux_media_server/features/video/presentation/utils/controls_api.dart';
import 'package:flux_media_server/features/video/presentation/utils/video_geometry.dart';
import 'package:flux_media_server/features/video/presentation/widgets/player_controls_layer.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_overlay.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Видеоконтроллер живёт столько же, сколько видео-плеер (синглтон).
/// Без onDispose: у VideoController нет dispose, а плеер чистит
/// videoPlayerDatasourceProvider.
final videoControllerProvider = Provider<VideoController>((ref) {
  final datasource = ref.watch(videoPlayerDatasourceProvider);
  return VideoController(
    datasource.player,
    configuration: VideoControllerConfiguration(
      // Аппаратное ускорение на Linux не работает (об этом известно в
      // media_kit), поэтому там его выключаем.
      // Через defaultTargetPlatform, а не dart:io: проект умеет
      // собираться под веб, где dart:io недоступен.
      enableHardwareAcceleration:
          defaultTargetPlatform != TargetPlatform.linux,
    ),
  );
});

/// Паузить ли видео при сносе панели (системный «назад»):
/// только своё играющее непоставленное видео. Чистая функция ради
/// тестируемости — сама панель требует нативный libmpv.
bool shouldPauseOnPanelDispose(PlaybackState playback, int mediaId) {
  return playback is PlaybackPlaying &&
      playback.type == MediaType.video &&
      playback.media.id == mediaId &&
      !playback.isPaused;
}

/// Паузить ли видео при УХОДЕ с экрана видео.
///
/// Отличие от [shouldPauseOnPanelDispose] — в смысле вызова: панель
/// пересоздаётся ещё и при смене режима (встроенная ⇄ полный экран),
/// и пауза на этом переходе выглядела бы как «видео встало при входе в
/// полный экран». Экран же пересоздаётся только при настоящем уходе.
bool shouldPauseOnScreenDispose(PlaybackState playback, int mediaId) {
  return shouldPauseOnPanelDispose(playback, mediaId);
}

class VideoPlayerPanel extends ConsumerStatefulWidget {
  const new({
    required this.media,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onClose,
    this.onPlay,
    super.key,
  });

  final Media media;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onClose;

  /// Запуск воспроизведения с кнопки поверх превью. Без него кнопки нет:
  /// на экране без трека запускать нечем.
  final VoidCallback? onPlay;

  @override
  ConsumerState<VideoPlayerPanel> createState() => _VideoPlayerPanelState();
}

class _VideoPlayerPanelState extends ConsumerState<VideoPlayerPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.isFullscreen) {
      _setFullscreenChrome(true);
    }
    // Создаём VideoController сразу: нативная текстура должна
    // прикрепиться к плееру до старта open().
    ref.read(videoControllerProvider);
  }

  /// Системный UI и ориентация экрана для полноэкранного режима.
  ///
  /// Ориентацию выбираем по размерам кадра из метаданных: альбомная для
  /// горизонтального видео (подавляющее большинство), книжная для
  /// вертикальных роликов. При выходе возвращаем все ориентации — раньше
  /// приложение не лочило ничего, и возвращать надо именно это состояние,
  /// иначе телефон остался бы в альбомной после просмотра.
  void _setFullscreenChrome(bool fullscreen) {
    final orientation = videoOrientationFor(
      width: widget.media.width,
      height: widget.media.height,
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    unawaited(
      SystemChrome.setPreferredOrientations(
        fullscreen
            ? orientationsFor(orientation)
            : const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      ),
    );
  }

  @override
  void didUpdateWidget(VideoPlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFullscreen && !oldWidget.isFullscreen) {
      _setFullscreenChrome(true);
    } else if (!widget.isFullscreen && oldWidget.isFullscreen) {
      _setFullscreenChrome(false);
    }
  }

  // Видео продолжает играть в фоне осознанно (как аудио): автопаузы
  // при сворачивании нет. Звонок фоновое видео не прерывает (прерывания
  // дёргают напрямую audio-движок) — известное ограничение.
  @override
  void dispose() {
    if (widget.isFullscreen) {
      _setFullscreenChrome(false);
    }
    // Паузы здесь НЕТ: dispose панели бывает и при смене режима
    // (встроенная ⇄ полный экран) — экран собирает другую ветвь дерева,
    // и панель пересоздаётся. Пауза на этом переходе выглядела бы как
    // «видео встало при входе в полный экран».
    //
    // Пауза при УХОДЕ с экрана — на стороне экрана (VideoDetailScreen),
    // где видно разницу между «сменили режим» и «покинули экран».
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      playbackCoordinatorProvider.select(playerViewFromPlaybackState),
    );

    final showLiveFrame = isOwnPlayingVideo(view, widget.media.id);
    final isPaused = view.kind == PlayerViewKind.playing && view.isPaused;

    // Кадр. Пропорции контейнера задаёт videoAspectRatioFor (для
    // встроенного режима), а как кадр вписывается в него — fit и
    // alignment ниже, заданы ЯВНО.
    //
    // Явно, а не «как у media_kit по умолчанию»: contain и по центру —
    // сейчас дефолты библиотеки, но полагаться на них молча нельзя.
    // Смена дефолта в апдейте media_kit тихо обрезала бы вертикальные
    // ролики по бокам, и это выглядело бы как баг в нашем коде.
    final video = Video(
      controller: ref.watch(videoControllerProvider),
      // Значения совпадают с дефолтами media_kit — в этом и смысл: они
      // зафиксированы здесь, чтобы смена дефолта в апдейте библиотеки не
      // обрезала вертикальные ролики по бокам. Линтер считает такое
      // «лишним», поэтому правило подавлено точечно.
      // ignore: avoid_redundant_argument_values
      fit: BoxFit.contain,
      // Тот же довод: alignment тоже фиксируем явно.
      // ignore: avoid_redundant_argument_values
      alignment: Alignment.center,
      // Стандартные контролы media_kit выключены: свой слой поверх.
      controls: _emptyControls,
    );

    // Порядок слоёв (кто сверху) задаёт VideoOverlay: интерактивные
    // элементы обязаны идти после слоя жестов, иначе тот забирает их
    // тапы — кнопка выглядит живой, но не нажимается.
    final overlay = VideoOverlay(
      // Постер — только если играет не это видео: иначе новая карточка
      // показывала бы чужой трек из синглтон-плеера. Если видео на паузе
      // своё, оставляем живой кадр: он и есть точка продолжения.
      poster: showLiveFrame ? null : _Poster(media: widget.media),
      controls: PlayerControlsLayer(
        api: MediaKitControlsApi(
          ref.watch(videoPlayerDatasourceProvider),
          // Громкость — через координатор: она общая на аудио и видео,
          // иначе на десктопе были бы два независимых регулятора.
          volumeWriter: (volume) => ref
              .read(playbackCoordinatorProvider.notifier)
              .setVolume(volume),
        ),
        isPaused: isPaused,
        showFullscreenButton: !widget.isFullscreen,
        onToggleFullscreen: widget.onToggleFullscreen,
        // Активна карточка только когда в плеере ИМЕННО это видео: иначе
        // транспортные кнопки правили бы чужой трек (см. isActive).
        isActive: showLiveFrame,
        onStart: widget.onPlay,
      ),
      // Кнопка play поверх превью — как в большинстве плееров. Раньше
      // такая же кнопка висела сильно ниже картинки, отдельным блоком,
      // и выглядело это так, будто она не относится к видео.
      playButton: !showLiveFrame && widget.onPlay != null
          ? Center(child: PlayOverlayButton(onPressed: widget.onPlay!))
          : null,
      // Кнопка «назад» в полноэкранном режиме.
      topBar: widget.isFullscreen && widget.onClose != null
          ? FullscreenBackButton(onClose: widget.onClose!)
          : null,
    );

    final body = Stack(fit: StackFit.expand, children: [video, overlay]);

    if (widget.isFullscreen) {
      return body;
    }
    return AspectRatio(
      aspectRatio: videoAspectRatioFor(
        width: widget.media.width,
        height: widget.media.height,
      ),
      child: body,
    );
  }
}

/// Пустой билдер контролов media_kit: свои контролы рисуются отдельным
/// слоем поверх, стандартные мешали бы (их таймер автоскрытия терялся
/// при пересборке `Video`).
Widget _emptyControls(VideoState state) => const SizedBox.shrink();

/// Показывать ли живой кадр плеера: играет именно это медиа.
/// Иначе — постер (чужой трек из общего плеера не подменяет карточку).
bool isOwnPlayingVideo(PlayerView view, int mediaId) {
  return view.kind == PlayerViewKind.playing &&
      view.type == MediaType.video &&
      view.media?.id == mediaId;
}

class _Poster extends ConsumerWidget {
  const new({required this.media});
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(baseUrlProvider);
    final url = buildMediaImageUrl(
      baseUrl: baseUrl,
      mediaId: media.id,
      kind: MediaImageKind.thumb,
      cacheBust: media.updatedAt?.millisecondsSinceEpoch,
    );
    return IgnorePointer(
      child: AuthNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

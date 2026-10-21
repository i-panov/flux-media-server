import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Слой управления видеоплеером поверх кадра media_kit.
///
/// Почему свой, а не `MaterialVideoControls` из media_kit_video:
/// стандартные контролы держат своё состояние видимости и таймер
/// автоскрытия ВНУТРИ виджета `Video`, который пересобирается на каждое
/// обновление состояния плеера — таймер при этом терялся, и тап по видео
/// срабатывал не с первого раза (интерфейс то появлялся, то нет).
/// Свой слой держит видимость у себя и перерисовывается только когда
/// меняется то, что на нём нарисовано.
///
/// Зоны жестов (как в YouTube):
/// - левая треть — двойной тап `−10 с`;
/// - правая треть — двойной тап `+10 с`;
/// - одиночный тап в любом месте — показать/скрыть контролы.
///
/// Одиночный тап срабатывает с задержкой в [kDoubleTapTimeout]: двойной
/// тап нельзя отличить от двух одиночных, не подождав. Это поведение
/// самого Flutter, ровно такое же в YouTube.
const kDoubleTapTimeout = Duration(milliseconds: 300);

/// Через сколько скрываются контролы после последнего действия.
const kControlsAutoHideDelay = Duration(seconds: 3);

/// Длительность вспышки «−10 с» / «+10 с» после двойного тапа.
const kSeekFeedbackDuration = Duration(milliseconds: 600);

/// Шаг перемотки двойным тапом и кнопками ±.
const kSeekStep = Duration(seconds: 10);

/// Скорости воспроизведения по кругу.
const kPlaybackRates = <double>[1, 1.5, 2, 0.5];

/// Нужен ли регулятор громкости в интерфейсе.
///
/// На смартфоне громкость живёт на физических кнопках, а в панели
/// только мешает; на десктопе её нечем менять, поэтому там регулятор
/// обязателен. Как в мини-плеере аудио.
///
/// Через `defaultTargetPlatform`, а не `dart:io`'s `Platform`: проект
/// умеет собираться под веб, где `dart:io` недоступен.
bool shouldShowVolumeControl() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// Ширина одной кнопки в нижнем ряду.
///
/// IconButton с tapTargetSize=padded (по умолчанию) всегда 48×48 — это
/// требование доступности (минимальная зона нажатия). Обойти его можно
/// только shrinkWrap'ом, которым жертвовать не стоит, поэтому ряд
/// подстраивается под 48, а не наоборот.
const _controlButtonWidth = 48.0;

/// Что показывать в нижнем ряду при данной ширине кадра.
///
/// Ряды кнопок в узком кадре не влезают: встроенный плеер на ноутбуке
/// — это 300–500 px. Переполнение выглядит как жёлто-полосатая полоса
/// поверх видео — хуже, чем лишние кнопки убрать.
enum ControlsLayout {
  /// Только полный экран — помещается в любой кадр.
  minimal,

  /// Плюс скорость (и кнопка звука на десктопе).
  full,

  /// Плюс ползунок громкости (только на десктопе).
  withVolumeSlider,
}

/// Выбирает состав нижнего ряда по ширине кадра.
///
/// [availableWidth] — ширина, доступная ряду (уже без отступов панели).
/// [withVolume] — есть ли в ряду кнопка звука и ползунок громкости
/// (десктоп; на смартфоне громкость живёт на физических кнопках).
ControlsLayout controlsLayoutFor(
  double availableWidth, {
  bool withVolume = false,
}) {
  // Состав ряда: скорость (48) + полный экран (48), на десктопе ещё
  // кнопка звука (48); ползунок громкости добавляет 110.
  const fullWidth = 2 * _controlButtonWidth;
  const desktopFullWidth = 3 * _controlButtonWidth;
  const sliderWidth = desktopFullWidth + 110;

  if (withVolume && availableWidth >= sliderWidth) {
    return ControlsLayout.withVolumeSlider;
  }
  final needed = withVolume ? desktopFullWidth : fullWidth;
  if (availableWidth >= needed) return ControlsLayout.full;
  return ControlsLayout.minimal;
}

/// Зона кадра, в которой сработал двойной тап.
enum SeekTapZone {
  /// Левая треть — отмотать назад.
  backward,

  /// Правая треть — перемотать вперёд.
  forward,

  /// Центр — ничего не делать: там же живёт одиночный тап, и двойной
  /// тап в центре не должен ни перематывать, ни прятать контролы.
  center,
}

/// Определяет зону по горизонтальной координате тапа.
///
/// Три равные части: крайние — перемотка, центр — только одиночный тап.
/// При нулевой ширине (layout ещё не измерен) возвращаем
/// [SeekTapZone.center]: перемотка по несуществующим координатам хуже,
/// чем её отсутствие.
SeekTapZone seekTapZoneFor(double localX, double width) {
  if (width <= 0) return SeekTapZone.center;
  final third = width / 3;
  if (localX < third) return SeekTapZone.backward;
  if (localX > 2 * third) return SeekTapZone.forward;
  return SeekTapZone.center;
}

/// Позиция перемотки по двойному тапу с клампом в границы файла.
///
/// Без клампа mpv получал бы отрицательный таргет при тапе в первые
/// секунды файла и таргет за концом — в конце.
Duration doubleTapSeekTarget({
  required Duration position,
  required SeekTapZone zone,
  required Duration duration,
}) {
  final step = zone == SeekTapZone.backward ? -kSeekStep : kSeekStep;
  final target = position + step;
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

/// Следующая скорость воспроизведения по кругу.
double nextPlaybackRate(double current) {
  final index = kPlaybackRates.indexOf(current);
  // Неизвестное значение (скорость выставлена где-то ещё) — начинаем
  // с 1.5x, а не с 0.5x: после обычного 1x это меньший скачок.
  return kPlaybackRates[index < 0 ? 1 : (index + 1) % kPlaybackRates.length];
}

/// Подпись перемотки: «−10s» / «+10s».
String seekFeedbackLabel(SeekTapZone zone) {
  final sign = zone == SeekTapZone.backward ? '−' : '+';
  return '$sign${kSeekStep.inSeconds}s';
}

/// Подпись скорости: «1x», «1.5x», «2x».
///
/// Без дробной части у целых: скорость приходит из mpv как double, и
/// наивная подстановка показывала бы «1.0x» — как в тесте, так и
/// на кнопке.
String playbackRateLabel(double rate) {
  return rate == rate.roundToDouble() ? '${rate.toInt()}x' : '${rate}x';
}

/// Плеер, к которому подключён слой.
abstract class PlayerControlsApi {
  /// Текущая позиция.
  Duration get position;

  /// Длительность файла (нулевая, пока файл не загружен).
  Duration get duration;

  /// Текущая скорость.
  double get rate;

  /// Скорость. Поток, а не разовый `setState` после `setRate`: скорость
  /// меняется и извне (например, с другого экрана или долгим нажатием в
  /// стандартных контролах), и кнопка обязана показать фактическое
  /// значение, а не своё устаревшее.
  Stream<double> get rateStream;

  /// Позиция (стрим тикает каждый кадр — на него подписан только сикбар).
  Stream<Duration> get positionStream;

  /// Длительность.
  Stream<Duration> get durationStream;

  /// Перемотать.
  Future<void> seek(Duration position);

  /// Запустить.
  Future<void> play();

  /// Пауза.
  Future<void> pause();

  /// Смена скорости.
  Future<void> setRate(double rate);

  /// Громкость (0..100).
  Future<void> setVolume(double volume);

  /// Текущая громкость (0..100).
  double get volume;

  /// Поток громкости: меняется и извне (например, системными кнопками
  /// на наушниках), кнопка обязана показывать фактическое значение.
  Stream<double> get volumeStream;
}

/// Слой контролов поверх видео: зоны жестов, автоскрытие, кнопки, сикбар.
class PlayerControlsLayer extends StatefulWidget {
  const new({
    required this.api,
    required this.isPaused,
    required this.onToggleFullscreen,
    this.isFullscreen = false,
    this.isActive = true,
    this.showVolumeControl = false,
    this.onStart,
    super.key,
  });

  final PlayerControlsApi api;

  /// На паузе кнопка показывает «играть», а контролы не автоскрываются:
  /// на паузе прятать нечего, а вернуться к управлению можно только
  /// тапом, о котором легко забыть.
  final bool isPaused;

  /// Переключение полного экрана. В полноэкранном режиме кнопка сворачивает
  /// видео обратно в карточку — отдельной стрелки «назад» больше нет.
  final VoidCallback? onToggleFullscreen;

  /// Полноэкранный ли режим: меняет иконку кнопки (развернуть/свернуть).
  final bool isFullscreen;

  /// Загружено ли это медиа в плеер.
  ///
  /// Плеер в приложении один на всё, и карточка видео может показывать
  /// постер, пока играет СОВСЕМ ДРУГОЙ трек (аудио из мини-плеера или
  /// другое видео). Тогда кнопки «пауза», «±10 с» и сикбар управляли
  /// бы чужим треком: пауза останавливала чужое аудио, сикбар показывал
  /// чужую длительность, а перемотка мотала чужое. Поэтому у неактивной
  /// карточки остаётся только запуск (тап по кадру) и полный экран.
  final bool isActive;

  /// Показывать ли регулятор громкости.
  ///
  /// На смартфоне громкость живёт на физических кнопках, и в панели она
  /// только мешает; на десктопе её нечем менять. Решение принимает
  /// вызывающая сторона (см. shouldShowVolumeControl), а слой получает
  /// готовый ответ: проверка платформы внутри виджета ломала бы его
  /// тестируемость.
  final bool showVolumeControl;

  /// Запуск этого медиа. Вызывается тапом по кадру, когда медиа ещё не
  /// загружено в плеер.
  final VoidCallback? onStart;

  @override
  State<PlayerControlsLayer> createState() => _PlayerControlsLayerState();
}

class _PlayerControlsLayerState extends State<PlayerControlsLayer> {
  bool _visible = true;
  Timer? _hideTimer;

  /// Зона последнего двойного тапа — для вспышки «−10 с».
  SeekTapZone? _flashZone;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerControlsLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      _showAndScheduleHide();
    }
    // Медиа загрузилось (или, наоборот, выгрузилось) — на активной
    // карточке контролы снова прячутся по таймеру, на неактивной
    // остаются видимыми.
    if (widget.isActive != oldWidget.isActive) {
      _showAndScheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _showAndScheduleHide() {
    if (!mounted) return;
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (widget.isPaused) return;
    // На неактивной карточке прятать нечего: там только кнопка полного
    // экрана. А тап по кадру на такой карточке уходит в запуск видео
    // (onStart), а не в переключение видимости — вернуть спрятанные
    // контролы было бы нечем, и кнопка «полный экран» пропадала бы
    // навсегда.
    if (!widget.isActive) return;
    _hideTimer = Timer(kControlsAutoHideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _togglePlayback() async {
    if (widget.isPaused) {
      await widget.api.play();
    } else {
      await widget.api.pause();
    }
    _showAndScheduleHide();
  }

  Future<void> _seekRelative(int sign) async {
    final target = doubleTapSeekTarget(
      position: widget.api.position,
      zone: sign < 0 ? SeekTapZone.backward : SeekTapZone.forward,
      duration: widget.api.duration,
    );
    await widget.api.seek(target);
    _showAndScheduleHide();
  }

  void _onDoubleTapDown(TapDownDetails details, double width) {
    final zone = seekTapZoneFor(details.localPosition.dx, width);
    if (zone == SeekTapZone.center) return;

    _flashTimer?.cancel();
    setState(() => _flashZone = zone);
    unawaited(_seekRelative(zone == SeekTapZone.backward ? -1 : 1));

    _flashTimer = Timer(kSeekFeedbackDuration, () {
      if (mounted) setState(() => _flashZone = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            // Зона жестов: под контролами, поэтому тапы по самим кнопкам
            // обрабатываются кнопками, а не здесь.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // На неактивной карточке одиночный тап запускает видео,
                // а не переключает видимость: показывать нечего, а
                // кнопка play поверх превью занимает только круг в
                // центре — тапнуть мимо него и не получить ничего
                // неудобно.
                onTap: widget.isActive
                    ? _toggleVisible
                    : () => widget.onStart?.call(),
                onDoubleTapDown: widget.isActive
                    ? (details) => _onDoubleTapDown(details, width)
                    : null,
                onDoubleTap: () {},
              ),
            ),
            if (_flashZone != null)
              Positioned.fill(
                child: IgnorePointer(child: _SeekFlash(zone: _flashZone!)),
              ),
            Positioned.fill(
              child: IgnorePointer(
                // Скрытые контролы не должны перехватывать тапы —
                // иначе одиночный тап для их показа не дошёл бы.
                //
                // Ключ — точка опоры для тестов видимости: анимированная
                // прозрачность оставляет виджеты в дереве, и по поиску
                // по иконкам «прятались/показались» не отличить.
                key: playerControlsVisibilityKey,
                ignoring: !_visible,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Stack(
                    children: [
                      // Кнопка play/pause по центру кадра. Она часть
                      // общей группы контролов: на паузе таймер автоскрытия
                      // не тикает, и кнопка остаётся видимой — вернуться
                      // к управлению можно только тапом, о котором легко
                      // забыть. При воспроизведении прячется вместе с
                      // остальными и появляется по тапу.
                      if (widget.isActive)
                        Center(
                          child: _CenterPlayButton(
                            isPaused: widget.isPaused,
                            onPressed: _togglePlayback,
                          ),
                        ),
                      _ControlsBar(
                        api: widget.api,
                        isPaused: widget.isPaused,
                        onTogglePlayback: _togglePlayback,
                        onSeekRelative: _seekRelative,
                        onToggleFullscreen: widget.onToggleFullscreen,
                        isFullscreen: widget.isFullscreen,
                        isActive: widget.isActive,
                        showVolumeControl: widget.showVolumeControl,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Вспышка «−10 с» / «+10 с» на соответствующей стороне кадра.
class _SeekFlash extends StatelessWidget {
  const new({required this.zone});

  final SeekTapZone zone;

  @override
  Widget build(BuildContext context) {
    final isBackward = zone == SeekTapZone.backward;
    return Align(
      alignment: isBackward ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBackward ? Icons.replay : Icons.forward,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  seekFeedbackLabel(zone),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Нижний блок: сикбар с временами и ряд кнопок.
class _ControlsBar extends StatelessWidget {
  const new({
    required this.api,
    required this.isPaused,
    required this.onTogglePlayback,
    required this.onSeekRelative,
    required this.onToggleFullscreen,
    required this.isFullscreen,
    required this.isActive,
    required this.showVolumeControl,
  });

  final PlayerControlsApi api;
  final bool isPaused;
  final Future<void> Function() onTogglePlayback;
  final Future<void> Function(int sign) onSeekRelative;
  final VoidCallback? onToggleFullscreen;

  /// Полноэкранный ли режим: меняет иконку кнопки полного экрана.
  final bool isFullscreen;

  /// Медиа загружено в плеер: только тогда транспорт имеет смысл.
  final bool isActive;

  /// Показывать ли регулятор громкости (десктоп).
  final bool showVolumeControl;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 28, 8, 4),
          child: Builder(
            // Builder, а не замыкание в StatelessWidget: тултипы кнопок
            // берутся из AppLocalizations, который доступен через context.
            builder: (context) {
              final l = AppLocalizations.of(context)!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Сикбар и транспорт — только для ЗАГРУЖЕННОГО медиа:
                  // иначе они показывают и правят чужой трек (см.
                  // isActive в PlayerControlsLayer).
                  if (isActive) _SeekBar(api: api),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Ряд кнопок в узком кадре не влезает: встроенный
                      // плеер на ноутбуке — это 300–500 px. Состав ряда
                      // подбирается по ширине (controlsLayoutFor),
                      // чтобы не было переполнения.
                      final layout = controlsLayoutFor(
                        constraints.maxWidth,
                        withVolume: showVolumeControl,
                      );
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Скорость — свойство ЗАГРУЖЕННОГО трека: на
                          // неактивной карточке менять нечего.
                          if (isActive &&
                              layout != ControlsLayout.minimal)
                            _SpeedControl(api: api),
                          // Громкость — только на десктопе: на смартфоне
                          // её меняют физическими кнопками, и в панели
                          // она бы только мешала.
                          if (isActive &&
                              showVolumeControl &&
                              layout != ControlsLayout.minimal)
                            _VolumeControl(
                              api: api,
                              showSlider:
                                  layout == ControlsLayout.withVolumeSlider,
                            ),
                          // Кнопка полного экрана — переключатель: в правом
                          // нижнем углу она разворачивает видео, а в
                          // полноэкранном режиме сворачивает обратно в
                          // карточку. Отдельной стрелки «назад» больше
                          // нет: в полном экране она всё равно висела
                          // поверх скрытых контролов.
                          if (onToggleFullscreen != null)
                            _ControlButton(
                              tooltip: isFullscreen
                                  ? l.exitFullscreen
                                  : l.fullscreen,
                              icon: Icon(
                                isFullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                              ),
                              onPressed: () => onToggleFullscreen!(),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Полоса прогресса со временами по краям.
///
/// Подписан на поток позиции сам: тики кадра перестраивают только его,
/// а не весь слой контролов.
class _SeekBar extends StatefulWidget {
  const new({required this.api});

  final PlayerControlsApi api;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.api.durationStream,
      initialData: widget.api.duration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: widget.api.positionStream,
          initialData: widget.api.position,
          builder: (context, positionSnap) {
            // Длительность неизвестна (файл грузится) — полосы нет: слайдер
            // с нулевым максимумом водит мышью по всей ширине.
            if (duration <= Duration.zero) {
              return const SizedBox(height: 32);
            }
            final max = duration.inMilliseconds.toDouble();
            final position =
                (_dragValue ??
                        positionSnap.data?.inMilliseconds.toDouble() ??
                        0)
                    .clamp(0.0, max);

            return LayoutBuilder(
              builder: (context, constraints) {
                // Подписи времени занимают около 100 px: в узком кадре
                // они вытесняли бы полосу прогресса, а та переполнялась бы
                // (жёлтые полосы). Тогда оставляем только саму полосу.
                final showTimes = constraints.maxWidth >= 200;
                return Row(
                  children: [
                    if (showTimes)
                      Text(
                        Duration(milliseconds: position.round()).formatted,
                        style: _timeStyle,
                      ),
                    Expanded(
                      child: SliderTheme(
                        data: const SliderThemeData(
                          trackHeight: 3,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: position,
                          max: max,
                          onChanged: (value) =>
                              setState(() => _dragValue = value),
                          // По отпусканию, а не на каждый пиксель: seek на
                          // каждый кадр перетаскивания дёргает mpv сильнее,
                          // чем нужно.
                          onChangeEnd: (value) {
                            unawaited(widget.api.seek(Duration(
                              milliseconds: value.round(),
                            )));
                            setState(() => _dragValue = null);
                          },
                        ),
                      ),
                    ),
                    if (showTimes)
                      Text(duration.formatted, style: _timeStyle),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  static const _timeStyle = TextStyle(color: Colors.white, fontSize: 12);
}

class _ControlButton extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;

  /// `null` — кнопка заблокирована (IconButton сам гасит её).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Размер кнопки НЕ задаём: IconButton с tapTargetSize по умолчанию
    // (padded) сам раздувает её до 48×48 — это требование доступности
    // (минимальная зона нажатия), и обойти его можно только
    // shrinkWrap'ом, которым жертвовать не стоит. Поэтому ряд
    // подстраивается под 48, а не наоборот.
    return IconButton(
      color: Colors.white,
      icon: icon,
      iconSize: 24,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

/// Скорость воспроизведения: 1x → 1.5x → 2x → 0.5x → 1x.
class _SpeedControl extends StatefulWidget {
  const new({required this.api});

  final PlayerControlsApi api;

  @override
  State<_SpeedControl> createState() => _SpeedControlState();
}

class _SpeedControlState extends State<_SpeedControl> {
  late double _rate;
  StreamSubscription<double>? _rateSub;

  @override
  void initState() {
    super.initState();
    _rate = widget.api.rate;
    // Подписан на поток, а не перерисовывается после своего же setRate:
    // скорость может сменить кто-то ещё (другая кнопка, долгое нажатие),
    // и тогда кнопка молча показывала бы старое значение.
    _rateSub = widget.api.rateStream.listen((rate) {
      if (mounted) setState(() => _rate = rate);
    });
  }

  @override
  void dispose() {
    unawaited(_rateSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      color: Colors.white,
      tooltip: l.speed,
      onPressed: () => unawaited(widget.api.setRate(nextPlaybackRate(_rate))),
      icon: Text(
        playbackRateLabel(_rate),
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

/// Регулятор громкости — только на десктопе (см. shouldShowVolumeControl).
///
/// Иконка + ползунок, как в мини-плеере аудио: на десктопе громкость
/// нечем менять иначе, а на смартфоне она на физических кнопках.
class _VolumeControl extends StatefulWidget {
  const new({required this.api, required this.showSlider});

  final PlayerControlsApi api;

  /// Показывать ползунок. В узком кадре ряд кнопок не помещается —
  /// тогда остаётся только кнопка отключения.
  final bool showSlider;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  late double _volume;
  StreamSubscription<double>? _volumeSub;

  /// Громкость до последнего отключения: по кнопке восстанавливается.
  double _volumeBeforeMute = 100;

  @override
  void initState() {
    super.initState();
    _volume = widget.api.volume;
    // Поток, а не setState после своего setVolume: громкость меняют и
    // системными кнопками на наушниках, и внешним плеером.
    _volumeSub = widget.api.volumeStream.listen((volume) {
      if (mounted) setState(() => _volume = volume);
    });
  }

  @override
  void dispose() {
    unawaited(_volumeSub?.cancel());
    super.dispose();
  }

  void _toggleMute() {
    final next = _volume > 0 ? 0.0 : _volumeBeforeMute;
    if (_volume > 0) _volumeBeforeMute = _volume;
    unawaited(widget.api.setVolume(next));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final muted = _volume <= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          color: Colors.white,
          tooltip: l.volume,
          onPressed: _toggleMute,
          icon: Icon(
            muted
                ? Icons.volume_off
                : _volume < 50
                ? Icons.volume_down
                : Icons.volume_up,
          ),
        ),
        if (widget.showSlider)
          SizedBox(
            width: 110,
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 3,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: _volume.clamp(0, 100),
                max: 100,
                onChanged: (value) =>
                    unawaited(widget.api.setVolume(value)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ключ контейнера с видимостью контролов.
///
/// `AnimatedOpacity` при нулевой прозрачности оставляет поддерево в
/// дереве, поэтому «спрятались ли контролы» по поиску иконок не
/// определить — проверяем состояние `IgnorePointer.ignoring` по этому ключу.
const playerControlsVisibilityKey = Key('player-controls-visibility');

/// Кнопка play/pause по центру кадра.
///
/// Как в обычных плеерах: на паузе она крупная и всегда на виду, при
/// воспроизведении прячется вместе с остальными контролами и
/// появляется по тапу. Без неё на паузе управление приходилось искать в
/// нижнем ряду, а он на узком кадре обрезается.
class _CenterPlayButton extends StatefulWidget {
  const new({required this.isPaused, required this.onPressed});

  final bool isPaused;
  final Future<void> Function() onPressed;

  @override
  State<_CenterPlayButton> createState() => _CenterPlayButtonState();
}

class _CenterPlayButtonState extends State<_CenterPlayButton> {
  /// Время последнего нажатия и состояние, при котором оно было.
  (DateTime, bool)? _lastTap;

  /// Окно, в котором второй тап считается «парой».
  static const _doubleTapGuard = Duration(milliseconds: 300);

  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTap;
    // Двойной тап по кнопке не должен переключать её дважды
    // (включил-выключил — как будто ничего не нажали).
    //
    // Защита по времени, а не через onDoubleTap: тот заставил бы
    // GestureDetector ждать таймаут двойного тапа, и одиночное нажатие
    // срабатывало бы на 300 мс позже — кнопка в центре кадра отвечала
    // бы с заметной паузой.
    //
    // Глушится только второй тап ТОГО ЖЕ действия: после «play» кнопка
    // становится «pause», и нажатие на неё — другое действие, его
    // выполнять надо (пользователь передумал).
    if (last != null &&
        last.$2 == widget.isPaused &&
        now.difference(last.$1) < _doubleTapGuard) {
      return;
    }
    _lastTap = (now, widget.isPaused);
    unawaited(widget.onPressed());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final label = widget.isPaused ? l.play : l.pause;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _handleTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                widget.isPaused ? Icons.play_arrow : Icons.pause,
                size: 44,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

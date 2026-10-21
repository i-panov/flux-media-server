import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/widgets/player_controls_layer.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Плеер-заглушка: пишет вызовы в списки, чтобы проверять жесты без
/// нативного libmpv.
class _FakeApi implements PlayerControlsApi {
  final List<Duration> seeks = [];
  final List<double> rates = [];
  final List<double> volumes = [];
  int playCalls = 0;
  int pauseCalls = 0;

  Duration currentPosition = const Duration(seconds: 30);
  Duration currentDuration = const Duration(minutes: 10);
  double currentRate = 1;
  double currentVolume = 100;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _rates = StreamController<double>.broadcast();
  final _volumes = StreamController<double>.broadcast();

  @override
  Stream<double> get rateStream => _rates.stream;

  @override
  double get volume => currentVolume;

  @override
  Stream<double> get volumeStream => _volumes.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get durationStream => _durations.stream;

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => currentDuration;

  @override
  double get rate => currentRate;

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> seek(Duration to) async => seeks.add(to);

  @override
  Future<void> setRate(double to) async {
    currentRate = to;
    rates.add(to);
    // mpv шлёт это событие сам (player.stream.rate) — фейк повторяет,
    // иначе тест проверял бы несуществующее поведение.
    _rates.add(to);
  }

  @override
  Future<void> setVolume(double to) async {
    currentVolume = to;
    volumes.add(to);
    _volumes.add(to);
  }

  /// Внешняя смена громкости: как будто её сделали системные кнопки
  /// на наушниках.
  void emitVolume(double to) {
    currentVolume = to;
    _volumes.add(to);
  }

  /// Внешняя смена скорости: как будто её сделали не этой кнопкой.
  void emitRate(double to) {
    currentRate = to;
    _rates.add(to);
  }

  void dispose() {
    unawaited(_positions.close());
    unawaited(_durations.close());
    unawaited(_rates.close());
    unawaited(_volumes.close());
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api, {
  bool isPaused = false,
  bool isActive = true,
  bool isFullscreen = false,
  bool showVolumeControl = false,
  VoidCallback? onStart,
  double width = 300,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 300,
            child: PlayerControlsLayer(
              api: api,
              isPaused: isPaused,
              isActive: isActive,
              isFullscreen: isFullscreen,
              showVolumeControl: showVolumeControl,
              onStart: onStart,
              onToggleFullscreen: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Одиночный тап: GestureDetector ждёт таймаут двойного, поэтому
/// `tester.tap` без последующего `pump` таймаута не даст `onTap`.
Future<void> _singleTapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

/// Видны ли контролы. По иконкам не проверить: при нулевой прозрачности
/// `AnimatedOpacity` держит поддерево в дереве.
bool _controlsVisible(WidgetTester tester) {
  final ignore = tester.widget<IgnorePointer>(
    find.byKey(playerControlsVisibilityKey),
  );
  return !ignore.ignoring;
}

/// Двойной тап двумя быстрыми тапами: `tester.tap` умеет только одиночный,
/// а без реальной пары тапов `GestureDetector` не вызовет `onDoubleTapDown`.
Future<void> _doubleTapAt(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kDoubleTapMinTime);
  await gesture.up();
  await tester.pump(kDoubleTapMinTime);
  final second = await tester.startGesture(at);
  await tester.pump(kDoubleTapMinTime);
  await second.up();
  await tester.pumpAndSettle();
}

void main() {
  group('seekTapZoneFor', () {
    test('левая треть — назад, правая — вперёд', () {
      expect(seekTapZoneFor(10, 300), SeekTapZone.backward);
      expect(seekTapZoneFor(99, 300), SeekTapZone.backward);
      expect(seekTapZoneFor(201, 300), SeekTapZone.forward);
      expect(seekTapZoneFor(299, 300), SeekTapZone.forward);
    });

    test('центр — только одиночный тап', () {
      expect(seekTapZoneFor(150, 300), SeekTapZone.center);
      expect(seekTapZoneFor(100, 300), SeekTapZone.center);
      expect(seekTapZoneFor(200, 300), SeekTapZone.center);
    });

    test('до измерения layout — центр, а не выдуманная перемотка', () {
      expect(seekTapZoneFor(10, 0), SeekTapZone.center);
    });
  });

  group('doubleTapSeekTarget', () {
    test('назад и вперёд на 10 секунд', () {
      const position = Duration(seconds: 30);
      expect(
        doubleTapSeekTarget(
          position: position,
          zone: SeekTapZone.backward,
          duration: const Duration(minutes: 10),
        ),
        const Duration(seconds: 20),
      );
      expect(
        doubleTapSeekTarget(
          position: position,
          zone: SeekTapZone.forward,
          duration: const Duration(minutes: 10),
        ),
        const Duration(seconds: 40),
      );
    });

    test('клампится в границы файла', () {
      // Без клампа mpv получал бы отрицательный таргет.
      expect(
        doubleTapSeekTarget(
          position: const Duration(seconds: 3),
          zone: SeekTapZone.backward,
          duration: const Duration(minutes: 10),
        ),
        Duration.zero,
      );
      expect(
        doubleTapSeekTarget(
          position: const Duration(seconds: 599),
          zone: SeekTapZone.forward,
          duration: const Duration(minutes: 10),
        ),
        const Duration(minutes: 10),
      );
    });

    test('при неизвестной длительности ограничивается снизу', () {
      expect(
        doubleTapSeekTarget(
          position: const Duration(seconds: 2),
          zone: SeekTapZone.backward,
          duration: Duration.zero,
        ),
        Duration.zero,
      );
    });
  });

  group('nextPlaybackRate', () {
    test('ходит по кругу и возвращается к 1x', () {
      expect(nextPlaybackRate(1), 1.5);
      expect(nextPlaybackRate(1.5), 2);
      expect(nextPlaybackRate(2), 0.5);
      expect(nextPlaybackRate(0.5), 1);
    });

    test('неизвестная скорость — шаг к 1.5x, а не прыжок к 0.5x', () {
      expect(nextPlaybackRate(3), 1.5);
    });
  });

  group('seekFeedbackLabel', () {
    test('знак соответствует зоне', () {
      expect(seekFeedbackLabel(SeekTapZone.backward), '−10s');
      expect(seekFeedbackLabel(SeekTapZone.forward), '+10s');
    });
  });

  group('playbackRateLabel', () {
    test('целые без дробной части, дробные как есть', () {
      // Скорость из mpv приходит double: наивная подстановка дала бы
      // «1.0x» на кнопке.
      expect(playbackRateLabel(1), '1x');
      expect(playbackRateLabel(2), '2x');
      expect(playbackRateLabel(1.5), '1.5x');
      expect(playbackRateLabel(0.5), '0.5x');
    });
  });

  group('controlsLayoutFor', () {
    test('узкий кадр — только полный экран', () {
      // Ряды кнопок в узком кадре не влезают: встроенный плеер на
      // ноутбуке — 300–500 px. Полный ряд (скорость + полный экран =
      // 96) туда ещё помещается, но на совсем узком — нет.
      expect(controlsLayoutFor(0), ControlsLayout.minimal);
      expect(controlsLayoutFor(95), ControlsLayout.minimal);
    });

    test('средний кадр — скорость и полный экран', () {
      expect(controlsLayoutFor(96), ControlsLayout.full);
      expect(controlsLayoutFor(500), ControlsLayout.full);
    });

    test('на десктопе ряд шире: добавляется кнопка звука', () {
      // С кнопкой звука ряд занимает 144: до этого места влезает
      // только скорость с полным экраном.
      expect(controlsLayoutFor(143, withVolume: true), ControlsLayout.minimal);
      expect(controlsLayoutFor(144, withVolume: true), ControlsLayout.full);
    });

    test('широкий кадр на десктопе — с ползунком громкости', () {
      expect(
        controlsLayoutFor(254, withVolume: true),
        ControlsLayout.withVolumeSlider,
      );
      expect(
        controlsLayoutFor(1200, withVolume: true),
        ControlsLayout.withVolumeSlider,
      );
    });

    test('на смартфоне ползунка громкости нет вовсе', () {
      // Громкость на смартфоне живёт на физических кнопках.
      expect(
        controlsLayoutFor(1200),
        ControlsLayout.full,
        reason: 'без регулятора звука ползунок не появляется',
      );
    });
  });

  group('PlayerControlsLayer', () {
    late _FakeApi api;

    setUp(() => api = _FakeApi());
    tearDown(() => api.dispose());

    testWidgets('контролы показаны сразу и прячутся по таймеру', (
      tester,
    ) async {
      await _pump(tester, api);
      expect(_controlsVisible(tester), isTrue);
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.pump(kControlsAutoHideDelay);
      await tester.pumpAndSettle();

      expect(_controlsVisible(tester), isFalse);
    });

    testWidgets('одиночный тап переключает видимость', (tester) async {
      await _pump(tester, api);
      await tester.pump(kControlsAutoHideDelay);
      await tester.pumpAndSettle();
      expect(_controlsVisible(tester), isFalse);

      // Тапаем в угол: в центре кадра стоит кнопка play/pause, и тап
      // достался бы ей, а не слою жестов.
      final layer = tester.getRect(find.byType(PlayerControlsLayer));
      final corner = Offset(layer.left + 20, layer.top + 20);

      // Одиночный тап подтверждается только после истечения таймаута
      // двойного — иначе его не отличить от первого тапа пары.
      await _singleTapAt(tester, corner);
      expect(_controlsVisible(tester), isTrue);

      // Повторный тап снова прячет — иначе показать/спрятать было бы
      // нечем, кроме как угадать момент автоскрытия.
      await _singleTapAt(tester, corner);
      expect(_controlsVisible(tester), isFalse);
    });

    testWidgets('кнопка play/pause по центру кадра', (tester) async {
      // Как в обычных плеерах: крупная кнопка в центре, при нажатии
      // видео играет. В нижнем ряду её больше нет — там тесно.
      await _pump(tester, api, isPaused: true);

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(api.playCalls, 1);
    });

    testWidgets('на паузе кнопка в центре не прячется по таймеру', (
      tester,
    ) async {
      // На паузе прятать нечего: вернуться к управлению можно только
      // тапом, о котором легко забыть.
      await _pump(tester, api, isPaused: true);

      await tester.pump(kControlsAutoHideDelay * 2);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('при воспроизведении кнопка в центре скрыта с контролами', (
      tester,
    ) async {
      await _pump(tester, api);

      await tester.pump(kControlsAutoHideDelay);
      await tester.pumpAndSettle();

      // Группа спряталась: элементы остаются в дереве с нулевой
      // прозрачностью, но нажать их уже нельзя.
      expect(_controlsVisible(tester), isFalse);
      // Кнопка в центре — часть этой группы, а не отдельный слой.
      expect(
        find.ancestor(
          of: find.byIcon(Icons.pause),
          matching: find.byKey(playerControlsVisibilityKey),
        ),
        findsOneWidget,
      );
    });

    testWidgets('двойной тап слева отматывает, справа — перематывает', (
      tester,
    ) async {
      await _pump(tester, api);
      final layer = tester.getRect(find.byType(PlayerControlsLayer));

      // Левая треть.
      await _doubleTapAt(tester, Offset(layer.left + 30, layer.center.dy));
      expect(api.seeks, [const Duration(seconds: 20)]);

      // Правая треть.
      api.seeks.clear();
      await _doubleTapAt(tester, Offset(layer.right - 30, layer.center.dy));
      expect(api.seeks, [const Duration(seconds: 40)]);
    });

    testWidgets('двойной тап в центре ничего не перематывает', (
      tester,
    ) async {
      await _pump(tester, api);
      final layer = tester.getRect(find.byType(PlayerControlsLayer));

      await _doubleTapAt(tester, Offset(layer.center.dx, layer.center.dy));

      expect(api.seeks, isEmpty);
    });

    testWidgets('вспышка «−10s» появляется и гаснет', (tester) async {
      await _pump(tester, api);
      final layer = tester.getRect(find.byType(PlayerControlsLayer));

      await _doubleTapAt(tester, Offset(layer.left + 30, layer.center.dy));
      expect(find.text('−10s'), findsOneWidget);

      await tester.pump(kSeekFeedbackDuration);
      await tester.pumpAndSettle();
      expect(find.text('−10s'), findsNothing);
    });

    testWidgets('кнопка play на паузе запускает, pause останавливает', (
      tester,
    ) async {
      await _pump(tester, api, isPaused: true);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      expect(api.playCalls, 1);

      // Родитель сообщает, что пошло воспроизведение: кнопка должна
      // переключиться на паузу (иначе она всегда показывала бы «play»).
      await _pump(tester, api);
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      expect(api.pauseCalls, 1);
    });

    testWidgets('на паузе контролы не автоскрываются', (tester) async {
      await _pump(tester, api, isPaused: true);

      await tester.pump(kControlsAutoHideDelay * 2);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow), findsWidgets);
    });

    testWidgets('кнопок ±10 секунд в ряду нет — перемотка двойным тапом', (
      tester,
    ) async {
      // Кнопки дублировали двойной тап по краям кадра и занимали место в
      // и без того тесном ряду. Остались только скорость, громкость и
      // полный экран.
      await _pump(tester, api, width: 700);

      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
    });

    testWidgets('кнопка скорости идёт по кругу', (tester) async {
      await _pump(tester, api, width: 700);
      expect(find.text('1x'), findsOneWidget);

      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();

      expect(api.rates, [1.5]);
      expect(find.text('1.5x'), findsOneWidget);
    });

    testWidgets('внешняя смена скорости видна на кнопке', (tester) async {
      // Регрессия: значение бралось из api.rate при build + setState после
      // СВОЕГО setRate. Смена скорости извне (другая кнопка, долгое
      // нажатие) оставалась незамеченной — до перерисовки слоя.
      await _pump(tester, api, width: 700);
      expect(find.text('1x'), findsOneWidget);

      api.emitRate(2);
      await tester.pumpAndSettle();

      expect(find.text('2x'), findsOneWidget);
    });

    testWidgets('тултипы кнопок локализованы', (tester) async {
      // ru-локаль: хардкод 'Play'/'Speed'/'Fullscreen' смешивал бы языки.
      await _pump(
        tester,
        api,
        isPaused: true,
        width: 700,
        locale: const Locale('ru'),
      );
      expect(find.byTooltip('Скорость'), findsOneWidget);
      expect(find.byTooltip('Полный экран'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      expect(find.byTooltip('Speed'), findsNothing);
      expect(find.byTooltip('Fullscreen'), findsNothing);
    });

    testWidgets('кнопка полного экрана в полном экране сворачивает', (
      tester,
    ) async {
      // Одна кнопка на оба состояния, в правом нижнем углу: развернуть
      // и свернуть обратно в карточку.
      await _pump(tester, api, width: 700, isFullscreen: true);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsNothing);

      await _pump(tester, api, width: 700);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
    });

    testWidgets('слой перехватывает тапы по всей площади кадра', (
      tester,
    ) async {
      // Свойство слоя, из-за которого кнопка play поверх превью обязана
      // идти ВЫШЕ него в Stack: GestureDetector на всю площадь забирает
      // тапы себе, и всё, что нарисовано под ним, не нажимается — кнопка
      // выглядела бы живой, но не реагировала бы.
      await _pump(tester, api);
      final layer = tester.getRect(find.byType(PlayerControlsLayer));

      // Тапаем в угол: в центре кадра стоит кнопка play/pause, и тап
      // достался бы ей, а не слою жестов.
      await _singleTapAt(tester, Offset(layer.left + 20, layer.top + 20));

      // Слой среагировал (переключил видимость), а не пропустил тап мимо.
      expect(api.seeks, isEmpty);
      expect(api.playCalls, 0);
      expect(_controlsVisible(tester), isFalse);
    });

    testWidgets('на активной карточке одиночный тап прячет контролы', (
      tester,
    ) async {
      // Поведение как в обычных плеерах: тап по видео переключает
      // видимость. Раньше (в стандартных контролах media_kit) тап
      // срабатывал не с первого раза — из-за потери таймера при
      // пересборке.
      await _pump(tester, api);
      expect(_controlsVisible(tester), isTrue);

      final layer = tester.getRect(find.byType(PlayerControlsLayer));
      await _singleTapAt(tester, Offset(layer.left + 20, layer.top + 20));

      expect(_controlsVisible(tester), isFalse);
    });

    testWidgets('на неактивной карточке транспорт скрыт', (tester) async {
      // Плеер в приложении один на всё. Пока в нём играет ДРУГОЙ трек
      // (аудио из мини-плеера), кнопки паузы/±10/скорость и сикбар
      // управляли бы и показывали чужое: пауза останавливала чужое
      // аудио, сикбар показывал чужую длительность.
      await _pump(tester, api, isActive: false);

      expect(find.byType(Slider), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
      expect(find.text('1x'), findsNothing);
      // Полный экран остаётся: он не зависит от того, что играет.
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    });

    testWidgets('на неактивной карточке тап по кадру запускает видео', (
      tester,
    ) async {
      var started = 0;
      await _pump(tester, api, isActive: false, onStart: () => started++);

      final layer = tester.getRect(find.byType(PlayerControlsLayer));
      await _singleTapAt(tester, Offset(layer.left + 20, layer.top + 20));

      expect(started, 1);
      // Показать/спрятать нечего — переключения видимости быть не должно.
      expect(_controlsVisible(tester), isTrue);
    });

    testWidgets('на неактивной карточке двойной тап не перематывает', (
      tester,
    ) async {
      await _pump(tester, api, isActive: false);

      final layer = tester.getRect(find.byType(PlayerControlsLayer));
      await _doubleTapAt(tester, Offset(layer.left + 30, layer.center.dy));

      expect(api.seeks, isEmpty);
    });

    testWidgets('регулятор громкости — только на десктопе', (tester) async {
      // На смартфоне громкость живёт на физических кнопках, и в панели
      // она только мешает; на десктопе её нечем менять.
      await _pump(tester, api, width: 700, showVolumeControl: true);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byTooltip('Volume'), findsOneWidget);

      await _pump(tester, api, width: 700);
      expect(find.byIcon(Icons.volume_up), findsNothing);
    });

    testWidgets('в узком кадре ряд урезан и не переполняется', (
      tester,
    ) async {
      // Ряд кнопок в узком кадре не влезает: переполнение (жёлтые
      // полосы) выглядело бы хуже, чем лишние кнопки.
      //
      // 80 px — уже не помещаются даже скорость с полным экраном
      // (2 кнопки по 48 = 96).
      await _pump(tester, api, width: 80);

      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.text('1x'), findsNothing);
    });

    testWidgets('в узком кадре остаётся только кнопка отключения', (
      tester,
    ) async {
      // В кадре средней ширины ползунок громкости уходит, но кнопка
      // отключения остаётся — иначе громкость на десктопе нечем было бы
      // менять вовсе.
      //
      // 200 px: ряд из трёх кнопок (скорость, звук, полный экран = 144)
      // помещается, а ползунок громкости (110) — уже нет.
      await _pump(tester, api, width: 200, showVolumeControl: true);

      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      // Ползунков в ряду один: сикбар позиции. Громкостного нет —
      // иначе ряд переполнился бы.
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('кнопка отключения глушит и восстанавливает громкость', (
      tester,
    ) async {
      await _pump(tester, api, width: 700, showVolumeControl: true);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pumpAndSettle();
      expect(api.volumes.last, 0);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_off));
      await tester.pumpAndSettle();
      // Вернулась громкость ДО отключения, а не дефолт 100.
      expect(api.volumes.last, 100);
    });

    testWidgets('внешняя смена громкости видна в регуляторе', (tester) async {
      // Громкость меняют и системными кнопками на наушниках — регулятор
      // обязан показывать фактическое значение.
      await _pump(tester, api, width: 700, showVolumeControl: true);
      api.emitVolume(20);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.volume_down), findsOneWidget);
    });

    testWidgets('сикбар появляется, когда известна длительность', (
      tester,
    ) async {
      await _pump(tester, api);
      // Длительность уже известна через геттер — полоса видна.
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('без длительности сикбар не рисуется', (tester) async {
      // Файл ещё грузится: слайдер с нулевым максимумом водил бы мышью
      // по всей ширине и «перематывал» в никуда.
      api.currentDuration = Duration.zero;
      await _pump(tester, api);

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('перемотка сикбаром уходит по отпусканию', (tester) async {
      await _pump(tester, api);
      final slider = find.byType(Slider);

      await tester.drag(slider, const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(api.seeks, isNotEmpty);
    });
  });
}

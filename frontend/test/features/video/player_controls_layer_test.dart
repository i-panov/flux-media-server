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
    test('узкий кадр — только play/pause и полный экран', () {
      // Ряды кнопок в узком кадре не влезают: встроенный плеер на
      // ноутбуке — 300–500 px. Полный ряд (6 кнопок по 48) плюс
      // ползунок громкости (110) туда не влезает.
      expect(controlsLayoutFor(0), ControlsLayout.minimal);
      expect(controlsLayoutFor(200), ControlsLayout.minimal);
      expect(controlsLayoutFor(287), ControlsLayout.minimal);
    });

    test('средний кадр — полный ряд без ползунка громкости', () {
      expect(controlsLayoutFor(288), ControlsLayout.full);
      expect(controlsLayoutFor(397), ControlsLayout.full);
    });

    test('широкий кадр — с ползунком громкости', () {
      expect(controlsLayoutFor(398), ControlsLayout.withVolumeSlider);
      expect(controlsLayoutFor(1200), ControlsLayout.withVolumeSlider);
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

      // Одиночный тап подтверждается только после истечения таймаута
      // двойного — иначе его не отличить от первого тапа пары.
      await _singleTapAt(tester, tester.getCenter(find.byType(PlayerControlsLayer)));
      expect(_controlsVisible(tester), isTrue);

      // Повторный тап снова прячет — иначе показать/спрятать было бы
      // нечем, кроме как угадать момент автоскрытия.
      await _singleTapAt(tester, tester.getCenter(find.byType(PlayerControlsLayer)));
      expect(_controlsVisible(tester), isFalse);
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

    testWidgets('кнопки ±10 секунд перематывают', (tester) async {
      await _pump(tester, api, width: 700);

      await tester.tap(find.byIcon(Icons.replay_10));
      await tester.pumpAndSettle();
      expect(api.seeks.last, const Duration(seconds: 20));

      await tester.tap(find.byIcon(Icons.forward_10));
      await tester.pumpAndSettle();
      expect(api.seeks.last, const Duration(seconds: 40));
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
      expect(find.byTooltip('Воспроизвести'), findsOneWidget);
      expect(find.byTooltip('Назад на 10 секунд'), findsOneWidget);
      expect(find.byTooltip('Вперёд на 10 секунд'), findsOneWidget);
      expect(find.byTooltip('Скорость'), findsOneWidget);
      expect(find.byTooltip('Полный экран'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);
      expect(find.byTooltip('Speed'), findsNothing);
      expect(find.byTooltip('Fullscreen'), findsNothing);
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

      // Одиночный тап в ЦЕНТРЕ — зона, где двойной тап ничего не делает
      // и куда кнопка play встаёт как раз при старте.
      await _singleTapAt(tester, Offset(layer.center.dx, layer.center.dy));

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
      await _singleTapAt(tester, Offset(layer.center.dx, layer.center.dy));

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
      await _pump(tester, api, width: 700);

      if (shouldShowVolumeControl()) {
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
        expect(find.byTooltip('Volume'), findsOneWidget);
      } else {
        expect(find.byIcon(Icons.volume_up), findsNothing);
      }
    });

    testWidgets('в узком кадре ряд урезан и не переполняется', (
      tester,
    ) async {
      // Ряд кнопок в узком кадре не влезает: переполнение (жёлтые
      // полосы) выглядело бы хуже, чем лишние кнопки.
      await _pump(tester, api, width: 280);

      // Только play/pause и полный экран.
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
      expect(find.text('1x'), findsNothing);
    });

    testWidgets('в узком кадре остаётся только кнопка отключения', (
      tester,
    ) async {
      // В кадре средней ширины ползунок громкости уходит, но кнопка
      // отключения остаётся — иначе громкость на десктопе нечем было бы
      // менять вовсе.
      if (!shouldShowVolumeControl()) return;

      await _pump(tester, api, width: 400);

      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      // Ползунков в ряду один: сикбар позиции. Громкостного нет —
      // иначе ряд переполнился бы.
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('кнопка отключения глушит и восстанавливает громкость', (
      tester,
    ) async {
      if (!shouldShowVolumeControl()) return;

      await _pump(tester, api, width: 700);
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
      if (!shouldShowVolumeControl()) return;

      await _pump(tester, api, width: 700);
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

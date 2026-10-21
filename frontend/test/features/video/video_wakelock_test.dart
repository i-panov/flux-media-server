import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/utils/video_wakelock.dart';

void main() {
  group('VideoWakelock', () {
    // Регрессия: media_kit_video держит флаг «не гасить экран» по потоку
    // playing и о lifecycle приложения не знает. В свёрнутом приложении флаг
    // оставался включённым — на iOS отключённый idle timer не давал
    // устройству уснуть, то есть фоновое воспроизведение съедало батарею.
    //
    // Теперь флаг держится только пока видео играет И приложение на
    // переднем плане.
    late List<bool> calls;
    late VideoWakelock wakelock;

    setUp(() {
      calls = [];
      wakelock = VideoWakelock.forTest(
        ({required enable}) async => calls.add(enable),
      );
    });

    test('видео играет на переднем плане — флаг включён', () async {
      wakelock.updatePlaying(playing: true);
      await pumpEventQueue();

      expect(calls, [true]);
    });

    test('уход в фон — флаг снят, видео продолжает играть', () async {
      wakelock.updatePlaying(playing: true);
      await pumpEventQueue();

      wakelock.updateForeground(foreground: false);
      await pumpEventQueue();

      expect(calls, [true, false]);
    });

    test('возврат из фона — флаг снова включён', () async {
      wakelock
        ..updatePlaying(playing: true)
        ..updateForeground(foreground: false);
      await pumpEventQueue();

      wakelock.updateForeground(foreground: true);
      await pumpEventQueue();

      expect(calls, [true, false, true]);
    });

    test('пауза видео — флаг снят', () async {
      wakelock.updatePlaying(playing: true);
      await pumpEventQueue();

      wakelock.updatePlaying(playing: false);
      await pumpEventQueue();

      expect(calls, [true, false]);
    });

    test('повторные сообщения не дёргают платформу', () async {
      wakelock
        ..updatePlaying(playing: true)
        ..updatePlaying(playing: true)
        ..updateForeground(foreground: true);
      await pumpEventQueue();

      expect(calls, [true]);
    });

    test('dispose снимает флаг', () async {
      wakelock.updatePlaying(playing: true);
      await pumpEventQueue();

      wakelock.dispose();
      await pumpEventQueue();

      expect(calls, [true, false]);
    });

    test('dispose без включённого флага ничего не делает', () async {
      wakelock.dispose();
      await pumpEventQueue();

      expect(calls, isEmpty);
    });
  });
}

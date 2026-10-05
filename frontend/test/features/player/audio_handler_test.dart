import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/audio_engine.dart';
import 'package:flux_media_server/features/player/data/audio_handler.dart';
import 'package:flux_media_server/features/player/data/datasources/audio_player_datasource.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:media_kit/media_kit.dart';

/// Подмена mpv-плеера: обычный объект, никакой нативной платформы.
class _FakeEngine implements AudioEngine {
  final playingCtl = StreamController<bool>.broadcast();
  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();
  final playlistCtl = StreamController<Playlist>.broadcast();
  final errorCtl = StreamController<String>.broadcast();
  final bufferingCtl = StreamController<bool>.broadcast();
  final volumeCtl = StreamController<double>.broadcast();

  Playlist? opened;
  final List<Media> added = [];
  final List<int> removed = [];
  final List<int> jumped = [];
  int nextCalls = 0;
  int previousCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<Duration> seeks = [];
  double setVolumeArg = 0;

  @override
  bool isPlaying = false;

  @override
  double volume = 100;

  /// Имитирует mpv с `--keep-open=yes`: следующий элемент включается сам.
  /// Меняет и сам плейлист — как mpv, который двигает playlist-playing-pos.
  void advanceTo(int index) {
    final current = opened;
    if (current == null || index < 0 || index >= current.medias.length) return;
    opened = current.copyWith(index: index);
    if (playlistCtl.isClosed) return;
    playlistCtl.add(opened!);
  }

  @override
  Future<void> open(Playlist playlist) async {
    opened = playlist;
    // media_kit шлёт stream.playlist сразу в open() (real.dart:168).
    _emitPlaylist();
  }

  @override
  Future<void> add(Media media) async {
    added.add(media);
    final current = opened;
    if (current == null) return;
    opened = current.copyWith(medias: [...current.medias, media]);
    _emitPlaylist();
  }

  @override
  Future<void> remove(int index) async {
    removed.add(index);
    final current = opened;
    if (current == null) return;
    final isPlayingLast =
        current.index == index && current.medias.length - 1 == index;
    final medias = [...current.medias]..removeAt(index);
    // Правило media_kit (real.dart:551-554): индекс уменьшается, только
    // если текущий БОЛЬШЕ удаляемого.
    final nextIndex = current.index > index
        ? current.index - 1
        : isPlayingLast
        ? (medias.length - 1 < 0 ? 0 : medias.length - 1)
        : current.index;
    opened = current.copyWith(medias: medias, index: nextIndex);
    if (isPlayingLast) {
      // Отдельная ветка media_kit (real.dart:504-528): удаление играющего
      // последнего элемента обрывает воспроизведение и шлёт синтетический
      // EOF — именно он приводит координатор в _onPlaylistCompleted.
      playingCtl.add(false);
      completedCtl.add(true);
    }
    _emitPlaylist();
  }

  void _emitPlaylist() {
    final current = opened;
    if (current == null || playlistCtl.isClosed) return;
    scheduleMicrotask(() {
      if (!playlistCtl.isClosed) playlistCtl.add(current);
    });
  }

  @override
  Future<void> jump(int index) async => jumped.add(index);

  @override
  Future<void> next() async => nextCalls++;

  @override
  Future<void> previous() async => previousCalls++;

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double volume) async => setVolumeArg = volume;

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  Stream<bool> get playingStream => playingCtl.stream;

  @override
  Stream<Duration> get positionStream => positionCtl.stream;

  @override
  Stream<Duration> get durationStream => durationCtl.stream;

  @override
  Stream<bool> get completedStream => completedCtl.stream;

  @override
  Stream<Playlist> get playlistStream => playlistCtl.stream;

  @override
  Stream<String> get errorStream => errorCtl.stream;

  @override
  Stream<bool> get bufferingStream => bufferingCtl.stream;

  @override
  Stream<double> get volumeStream => volumeCtl.stream;

  Future<void> close() async {
    for (final c in [
      playingCtl,
      positionCtl,
      durationCtl,
      completedCtl,
      playlistCtl,
      errorCtl,
      bufferingCtl,
      volumeCtl,
    ]) {
      await c.close();
    }
  }
}

AudioQueueEntry _entry(
  int id, {
  String? artUri,
  Map<String, String>? headers,
}) => AudioQueueEntry(
  mediaId: id,
  url: 'http://test/media/$id/stream',
  title: 'Track $id',
  artist: 'Artist $id',
  artUri: artUri,
  duration: const Duration(minutes: 3),
  httpHeaders: headers,
);

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeEngine engine;
  late List<({String url, Map<String, String>? headers})> artRequests;
  late List<FluxAudioHandler> handlers;

  FluxAudioHandler build({ArtworkFetcher? artworkFetcher}) {
    final handler = FluxAudioHandler(
      engine: engine,
      artworkFetcher:
          artworkFetcher ??
          (url, headers) async {
            artRequests.add((url: url, headers: headers));
            return null;
          },
    );
    handlers.add(handler);
    return handler;
  }

  setUp(() {
    engine = _FakeEngine();
    artRequests = [];
    handlers = [];
  });

  tearDown(() async {
    for (final handler in handlers) {
      await handler.dispose();
    }
    await engine.close();
  });

  group('FluxAudioHandler routing: mpv-команды против колбэков', () {
    test(
      'next()/previous() идут в движок и НЕ трогают onNext/onPrevious',
      () async {
        final handler = build();
        var onNextCalls = 0;
        var onPreviousCalls = 0;
        handler
          ..onNext = () async {
            onNextCalls++;
            return true;
          }
          ..onPrevious = () async {
            onPreviousCalls++;
            return true;
          };

        await handler.next();
        await handler.previous();

        // Регресс: если next() снова начнёт дёргать onNext, координатор,
        // вызывающий его из _onCompleted, попадёт в очередь → next() →
        // координатор и намертво заблокирует цепочку запусков.
        expect(engine.nextCalls, 1);
        expect(engine.previousCalls, 1);
        expect(onNextCalls, 0);
        expect(onPreviousCalls, 0);
      },
    );

    test(
      'skipToNext()/skipToPrevious() дёргают колбэки и НЕ трогают движок',
      () async {
        final handler = build();
        final onNextCalls = <String>[];
        handler
          ..onNext = () async {
            onNextCalls.add('next');
            return true;
          }
          ..onPrevious = () async {
            onNextCalls.add('previous');
            return true;
          };

        await handler.skipToNext();
        await handler.skipToPrevious();

        // Регресс: audio_service маршрутизирует MediaAction.skipToNext в
        // skipToNext(), а BaseAudioHandler.skipToNext() — пустая заглушка.
        // Без override кнопки уведомления/лок-скрина/гарнитуры мертвы.
        expect(onNextCalls, ['next', 'previous']);
        expect(engine.nextCalls, 0);
        expect(engine.previousCalls, 0);
      },
    );

    test('jump()/remove() идут в движок, минуя колбэки', () async {
      final handler = build();
      var onNextCalls = 0;
      handler.onNext = () async {
        onNextCalls++;
        return true;
      };

      await handler.loadPlaylist([_entry(1), _entry(2)], startIndex: 0);
      await handler.jump(1);
      await handler.remove(0);

      expect(engine.jumped, [1]);
      expect(engine.removed, [0]);
      expect(onNextCalls, 0);
    });

    test('play() идёт в onPlay, если он задан, иначе в движок', () async {
      final handler = build();
      var onPlayCalls = 0;
      handler.onPlay = () async => onPlayCalls++;

      await handler.play();
      expect(onPlayCalls, 1);
      expect(engine.playCalls, 0);

      // Без делегата (например, в тестах) — прямая mpv-команда.
      final bare = build();
      await bare.play();
      expect(engine.playCalls, 1);
    });

    test('playDirect() всегда идёт в движок, минуя onPlay', () async {
      // Регресс: если бы координатор вызывал handler.play() вместо
      // playDirect(), из resume() он ушёл бы в onPlay → resume() → play() →
      // onPlay (бесконечная рекурсия), а из _startQueue (состояние
      // loading) onPlay не сделал бы ничего и playback не стартовал бы.
      final handler = build();
      var onPlayCalls = 0;
      handler.onPlay = () async => onPlayCalls++;

      await handler.playDirect();

      expect(engine.playCalls, 1);
      expect(onPlayCalls, 0);
    });

    test('next() через datasource идёт в движок, а не в onNext', () async {
      // Раньше datasource звал engine.next() в обход хендлера, и
      // тестируемая маршрутизация не покрывала продовый путь.
      final handler = build();
      var onNextCalls = 0;
      var onPlayCalls = 0;
      handler
        ..onNext = () async {
          onNextCalls++;
          return true;
        }
        ..onPlay = () async => onPlayCalls++;
      final datasource = AudioPlayerDatasource(handler);

      await datasource.next();
      await datasource.previous();
      await datasource.play();

      expect(engine.nextCalls, 1);
      expect(engine.previousCalls, 1);
      expect(engine.playCalls, 1);
      expect(onNextCalls, 0);
      // С onPlay заданным playDirect() обязан был уйти в движок, а не в
      // делегат: handler.play() увёл бы координатор в resume() → play() →
      // onPlay (рекурсия), а из loading не сделал бы ничего.
      expect(onPlayCalls, 0);
    });
  });

  group('FluxAudioHandler playlist metadata', () {
    test('loadPlaylist ставит MediaItem сразу и публикует индекс', () async {
      final handler = build();

      await handler.loadPlaylist([
        _entry(1),
        _entry(2),
        _entry(3),
      ], startIndex: 0);
      // MediaItem есть сразу, без обложки: уведомление не ждёт сеть.
      expect(handler.mediaItem.value?.title, 'Track 1');
      await _settle();
      expect(handler.playlistIndex, 0);

      final seen = <int>[];
      final sub = handler.playlistIndexStream.listen(seen.add);
      addTearDown(sub.cancel);

      engine.advanceTo(1);
      await _settle();

      expect(seen, [1]);
      expect(handler.playlistIndex, 1);
      expect(handler.mediaItem.value?.title, 'Track 2');
    });

    test('loadPlaylist возвращается ДО завершения загрузки обложки', () async {
      // Регресс на тот же класс багов, что и у сохранения прогресса:
      // сетевой запрос в критическом пути перехода. Обложка
      // (audio_service не шлёт Authorization) качается с auth-заголовками,
      // и в фоне этот запрос упирался в таймаут — музыка молчала.
      final gate = Completer<File?>();
      final calls = <String>[];
      final handler = build(
        artworkFetcher: (url, headers) {
          calls.add(url);
          return gate.future;
        },
      );

      await handler.loadPlaylist([
        _entry(1, artUri: 'http://test/media/1/cover'),
      ], startIndex: 0);

      // loadPlaylist вернулся, хотя fetcher ещё висит на gate: если бы он
      // ждал скачивание, метод не вернулся бы и тест упал бы по таймауту.
      expect(engine.opened, isNotNull);
      expect(handler.mediaItem.value?.title, 'Track 1');
      expect(handler.mediaItem.value?.artUri, isNull);
      // artRequests здесь был бы вхолостую: его наполняет дефолтный
      // fetcher, а в тесте подставлен свой.
      await _settle();
      expect(calls.single, 'http://test/media/1/cover');
    });

    test('обложка одного трека скачивается ровно один раз', () async {
      // Стартовый трек зовёт _loadArtworkFor и из слушателя playlistStream
      // (он срабатывает внутри await engine.open), и явно. Проверка кеша
      // стоит до первого await, поэтому без _artInFlight оба вызова
      // проходили её и делали по два HTTP GET в один файл.
      final calls = <String>[];
      final handler = build(
        artworkFetcher: (url, headers) async {
          calls.add(url);
          return null;
        },
      );

      await handler.loadPlaylist([
        _entry(1, artUri: 'http://test/media/1/cover'),
        _entry(2, artUri: 'http://test/media/2/cover'),
      ], startIndex: 0);
      await _settle();

      expect(calls, ['http://test/media/1/cover']);
    });

    test('обложка доезжает позже и подхватывается MediaItem', () async {
      final gate = Completer<File?>();
      final handler = build(artworkFetcher: (url, headers) => gate.future);

      await handler.loadPlaylist([
        _entry(1, artUri: 'http://test/media/1/cover', headers: const {}),
      ], startIndex: 0);
      expect(handler.mediaItem.value?.artUri, isNull);

      final tmp = File(
        '${Directory.systemTemp.path}/flux_test_art_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete();
      });
      gate.complete(tmp);
      await _settle();

      expect(handler.mediaItem.value?.artUri, tmp.uri);
    });

    test('remove(index) держит _entries в синхроне с mpv-индексом', () async {
      // Регресс: remove() вызывал только player.remove, _entries оставался
      // прежним, и событие stream.playlist брало метаданные соседнего
      // трека — в уведомлении езжали не те название и обложка.
      final handler = build();
      await handler.loadPlaylist([
        _entry(1),
        _entry(2),
        _entry(3),
      ], startIndex: 0);
      engine.advanceTo(1);
      await _settle();
      expect(handler.mediaItem.value?.title, 'Track 2');

      await handler.remove(1);
      await _settle();
      // mpv ушёл на индекс 1 = трек 3.
      expect(engine.removed, [1]);
      expect(handler.mediaItem.value?.title, 'Track 3');
      expect(handler.mediaItem.value?.artist, 'Artist 3');
      expect(handler.mediaItem.value?.id, 'http://test/media/3/stream');
    });

    test(
      'удаление играющего последнего элемента шлёт синтетический EOF',
      () async {
        // Отдельная ветка media_kit (real.dart:504-528): индекс уезжает на
        // length-2, воспроизведение встаёт и приходит completed=true. Именно
        // этот EOF приводит координатор в _onPlaylistCompleted — ветка была не
        // покрыта, и mpv-специфика при удалении не моделировалась.
        final handler = build();
        await handler.loadPlaylist([
          _entry(1),
          _entry(2),
          _entry(3),
        ], startIndex: 2);
        await _settle();
        expect(handler.playlistIndex, 2);
        final completed = <bool>[];
        final sub = handler.completedStream.listen(completed.add);
        addTearDown(sub.cancel);

        await handler.remove(2);
        await _settle();

        expect(engine.removed, [2]);
        expect(handler.playlistIndex, 1);
        expect(handler.mediaItem.value?.title, 'Track 2');
        expect(completed, [true]);
      },
    );

    test('remove(index) игнорирует выход за границы', () async {
      final handler = build();
      await handler.loadPlaylist([_entry(1), _entry(2)], startIndex: 0);

      await handler.remove(5);
      await handler.remove(-1);

      expect(engine.removed, isEmpty);
    });

    test('appendToPlaylist дописывает и в движок, и в метаданные', () async {
      final handler = build();
      await handler.loadPlaylist([_entry(1)], startIndex: 0);

      await handler.appendToPlaylist([
        _entry(2, headers: const {'Authorization': 'Bearer t'}),
      ]);
      await _settle();

      expect(engine.added, hasLength(1));
      expect(engine.added.single.uri, 'http://test/media/2/stream');
      expect(engine.added.single.httpHeaders, const {
        'Authorization': 'Bearer t',
      });
      expect(engine.opened?.medias, hasLength(2));
      // Текущий трек не сменился.
      expect(handler.mediaItem.value?.title, 'Track 1');
    });

    test('stop() сбрасывает индекс и отдаёт управление движку', () async {
      final handler = build();
      await handler.loadPlaylist([_entry(1), _entry(2)], startIndex: 0);
      engine.advanceTo(1);
      await _settle();
      expect(handler.playlistIndex, 1);

      await handler.stop();

      expect(engine.stopCalls, 1);
      expect(handler.playlistIndex, -1);
    });
  });
}

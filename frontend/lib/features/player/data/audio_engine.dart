import 'package:media_kit/media_kit.dart';

/// Узкий интерфейс поверх media_kit [Player], которым пользуется
/// `FluxAudioHandler`.
///
/// Существует ради тестируемости: настоящий `Player` eagerly создаёт
/// `NativePlayer`, а тот через `dlopen` подтягивает libmpv, которого в
/// `flutter test` нет. Плоский интерфейс позволяет подменить движок фейком
/// и покрыть маршрутизацию команд (mpv-команда против колбэка системного
/// уведомления) — именно там дважды проскакивали регрессии.
abstract interface class AudioEngine {
  /// Открывает весь плейлист сразу и стартует с [index].
  Future<void> open(Playlist playlist);

  Future<void> add(Media media);
  Future<void> remove(int index);
  Future<void> jump(int index);
  Future<void> next();
  Future<void> previous();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();

  bool get isPlaying;
  double get volume;

  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get completedStream;
  Stream<Playlist> get playlistStream;
  Stream<String> get errorStream;
  Stream<bool> get bufferingStream;
  Stream<double> get volumeStream;
}

/// Продакшн-реализация [AudioEngine] поверх media_kit [Player].
///
/// Тонкая делегация: media_kit сам применяет `httpHeaders` при загрузке
/// каждого файла плейлиста, а индекс переключения приходит отдельным
/// событием [playlistStream].
class MediaKitAudioEngine implements AudioEngine {
  new({required this._player});

  final Player _player;

  @override
  Future<void> open(Playlist playlist) => _player.open(playlist);

  @override
  Future<void> add(Media media) => _player.add(media);

  @override
  Future<void> remove(int index) => _player.remove(index);

  @override
  Future<void> jump(int index) => _player.jump(index);

  @override
  Future<void> next() => _player.next();

  @override
  Future<void> previous() => _player.previous();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();

  @override
  bool get isPlaying => _player.state.playing;

  @override
  double get volume => _player.state.volume;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<Playlist> get playlistStream => _player.stream.playlist;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<double> get volumeStream => _player.stream.volume;
}

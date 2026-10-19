import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/features/video/presentation/widgets/player_controls_layer.dart';

/// Адаптер плеера media_kit к [PlayerControlsApi].
///
/// Отдельный класс, а не реализация интерфейса прямо в datasource:
/// слой контролов не должен знать про media_kit, а datasource — про UI.
class MediaKitControlsApi implements PlayerControlsApi {
  const new(this.source, {this.volumeWriter});

  final VideoPlaybackSource source;

  /// Куда писать громкость.
  ///
  /// По умолчанию — в сам видеоплеер. Но громкость в приложении общая
  /// (аудио+видео), поэтому экран передаёт координатор: иначе убавленный
  /// в видеоплеере звук не влиял бы на аудио, и на десктопе получались
  /// два независимых регулятора.
  final Future<void> Function(double volume)? volumeWriter;

  @override
  Duration get position => source.position;

  @override
  Duration get duration => source.duration;

  @override
  double get rate => source.rate;

  @override
  Stream<double> get rateStream => source.rateStream;

  @override
  Stream<Duration> get positionStream => source.positionStream;

  @override
  Stream<Duration> get durationStream => source.durationStream;

  @override
  Future<void> seek(Duration position) => source.seek(position);

  @override
  Future<void> play() => source.play();

  @override
  Future<void> pause() => source.pause();

  @override
  Future<void> setRate(double rate) => source.setRate(rate);

  @override
  Future<void> setVolume(double volume) async {
    final writer = volumeWriter;
    if (writer != null) {
      await writer(volume);
      return;
    }
    await source.setVolume(volume);
  }

  @override
  double get volume => source.volume;

  @override
  Stream<double> get volumeStream => source.volumeStream;
}

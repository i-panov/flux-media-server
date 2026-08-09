import 'package:characters/characters.dart';

extension StringExtensions on String {
  String get capitalize {
    if (isEmpty) return this;
    final chars = Characters(this);
    final first = chars.first;
    return '$first${chars.skip(1)}'.replaceFirst(first, first.toUpperCase());
  }
}

extension DurationExtensions on Duration {
  String get formatted {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    final h = hours.toString().padLeft(2, '0');
    final m = minutes.toString().padLeft(2, '0');
    final s = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }
}

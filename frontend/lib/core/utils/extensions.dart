extension StringExtensions on String {
  String get capitalize {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

extension DurationExtensions on Duration {
  String get formatted {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    if (hours > 0) {
      return "${hours.toString().padLeft(2, "0")}:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
    }
    return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }
}

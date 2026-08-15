/// Регулярка LRC-таймкода `[mm:ss.xx]`.
final RegExp lrcTimeCodeRegExp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');

/// Разбор LRC-синхронизации в записи (время, текст).
///
/// - Доли секунд сохраняются полностью (микросекунды), а не обрезаются
///   `seconds.toInt()` — иначе подсветка строк «плавает» на 0.5–0.9 с.
/// - Строка с несколькими таймкодами (`[00:10][00:20]текст`) порождает
///   запись на каждый таймкод.
List<({Duration time, String text})> parseSyncedLyrics(String syncData) {
  if (syncData.isEmpty) return [];
  final result = <({Duration time, String text})>[];

  for (final rawLine in syncData.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final matches = lrcTimeCodeRegExp.allMatches(line).toList();
    if (matches.isEmpty) continue;

    final text = line.substring(matches.last.end).trim();
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = double.parse(match.group(2)!);
      final microseconds = ((minutes * 60 + seconds) * 1000000).round();
      result.add((time: Duration(microseconds: microseconds), text: text));
    }
  }
  return result;
}

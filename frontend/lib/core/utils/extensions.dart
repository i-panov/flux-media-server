import 'package:flutter/widgets.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Короткий доступ к локализации: `context.l10n.showAll` вместо
/// `AppLocalizations.of(context)!.showAll`.
///
/// Раньше каждая строка на экране начиналась с `AppLocalizations.of(context)!`
/// — это и шум, и риск `!` на пустом контексте.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n {
    final l = AppLocalizations.of(this);
    // Null возможен только без MaterialApp с делегатами выше — в этом
    // приложении и тестах недостижимо, но дебагу нужен понятный текст,
    // а не «Null check operator used on a null value».
    assert(
      l != null,
      'l10n used outside MaterialApp with AppLocalizations delegates',
    );
    return l!;
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

import 'package:flutter/material.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Композиция слоёв поверх кадра видео.
///
/// Порядок в [Stack] задаёт ПРАВО нажатия, а не только перекрытие:
/// последний ребёнок сверху, и тап достаётся ему. Поэтому
/// интерактивные элементы идут после слоя жестов:
///
/// - [controls] — слой с GestureDetector на всю площадь кадра; он
///   перехватывает тапы, поэтому под ним ничего не нажимается;
/// - [playButton] — круглая кнопка запуска поверх превью; идёт после
///   [controls], иначе тап по ней прятал бы контролы вместо запуска.
///
/// Вынесено отдельным виджетом не ради красоты: порядок слоёв —
/// ровно тот случай, когда опечатка в списке даёт «кнопка выглядит
/// живой, но не нажимается», и такой баг не видно ни в коде, ни на
/// виджет-тестах панели (она требует нативного libmpv).
class VideoOverlay extends StatelessWidget {
  const new({
    required this.poster,
    required this.controls,
    this.playButton,
    super.key,
  });

  /// Постер (или `null`, если показывается живой кадр).
  final Widget? poster;

  /// Слой управления: жесты, сикбар, кнопки.
  final Widget? controls;

  /// Круглая кнопка запуска поверх превью.
  final Widget? playButton;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ?poster,
        ?controls,
        ?playButton,
      ],
    );
  }
}

/// Полупрозрачная круглая кнопка play поверх превью.
class PlayOverlayButton extends StatelessWidget {
  const new({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l.play,
      child: Tooltip(
        message: l.play,
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: const SizedBox(
              width: 64,
              height: 64,
              child: Icon(Icons.play_arrow, size: 40, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

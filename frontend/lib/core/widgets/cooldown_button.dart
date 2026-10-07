import 'dart:async';

import 'package:flutter/material.dart';

/// Обратный отсчёт до повторного действия.
///
/// Два идентичных таймера жили в `login_screen` (кнопка «получить код») и
/// `code_screen` («отправить ещё раз»). Состояние и тик — здесь, экраны
/// остаются со своей разметкой.
class CooldownController extends ChangeNotifier {
  new(this._duration);

  final Duration _duration;

  Timer? _timer;

  Duration _elapsed = Duration.zero;

  /// Отсчёт запущен хотя бы раз. До первого `start()` кнопка доступна:
  /// иначе экраны входа показывали бы «Получить код (30s)» в disabled.
  bool _started = false;

  /// Осталось секунд; 0 — действие доступно.
  int get remaining => _started ? _duration.inSeconds - _elapsed.inSeconds : 0;
  bool get isActive => _started && remaining > 0;

  /// Запустить отсчёт заново (повторное нажатие не продлевает его).
  void start() {
    _timer?.cancel();
    _started = true;
    _elapsed = Duration.zero;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsed += const Duration(seconds: 1);
      if (_elapsed >= _duration) {
        timer.cancel();
        _timer = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Кнопка с обратным отсчётом: подпись `label (12s)`, пока [cooldown]
/// активен — нажатия заблокированы.
class CooldownButton extends StatelessWidget {
  const new({
    required this.cooldown,
    required this.onPressed,
    required this.label,
    super.key,
    this.loading = false,
  });

  final CooldownController cooldown;
  final VoidCallback? onPressed;
  final String label;

  /// Спиннер вместо подписи на время самой операции.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cooldown,
      builder: (context, _) {
        final enabled = !cooldown.isActive && !loading;
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: enabled ? onPressed : null,
            child: loading
                ? const CircularProgressIndicator()
                : Text(
                    cooldown.isActive
                        ? '$label (${cooldown.remaining}s)'
                        : label,
                  ),
          ),
        );
      },
    );
  }
}

/// Текстовая кнопка с обратным отсчётом — для «отправить код ещё раз».
class CooldownTextButton extends StatelessWidget {
  const new({
    required this.cooldown,
    required this.onPressed,
    required this.label,
    super.key,
    this.enabled = true,
  });

  final CooldownController cooldown;
  final VoidCallback? onPressed;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cooldown,
      builder: (context, _) {
        final isEnabled = enabled && !cooldown.isActive;
        return Semantics(
          label: label,
          enabled: isEnabled,
          button: true,
          child: TextButton(
            onPressed: isEnabled ? onPressed : null,
            child: Text(
              cooldown.isActive ? '$label (${cooldown.remaining}s)' : label,
            ),
          ),
        );
      },
    );
  }
}

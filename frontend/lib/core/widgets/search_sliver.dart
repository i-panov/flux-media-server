import 'package:flutter/material.dart';
import 'package:flux_media_server/core/utils/extensions.dart';

/// Строка поиска как sliver — общая для видео-, аудио- и артист-экранов.
///
/// Раньше одинаковый `SearchBar` в `trailing`-иконкой копировался три
/// раза; здесь же живёт и `PopScope`-обвязка, которая тоже повторялась.
class SearchSliver extends StatelessWidget {
  const new({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onCleared,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SearchBar(
          controller: controller,
          hintText: hintText,
          leading: const Icon(Icons.search),
          trailing: [
            // ValueListenableBuilder вместо setState на каждый символ.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => IconButton(
                icon: const Icon(Icons.close),
                tooltip: context.l10n.cancel,
                onPressed: value.text.isEmpty ? null : onCleared,
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Системный back при активном поиске сначала очищает поиск (возврат к
/// полному списку), а не «проглатывается» корневым `PopScope` (выход из
/// приложения на мобильных).
///
/// `ListenableBuilder` обязателен: `canPop` должен обновляться на каждый
/// символ, а не при rebuild экрана — иначе в окне до debounce back
/// выходит из приложения.
class SearchPopScope extends StatelessWidget {
  const new({
    required this.controller,
    required this.onCleared,
    required this.child,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onCleared;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope(
        canPop: controller.text.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onCleared();
        },
        child: child,
      ),
    );
  }
}

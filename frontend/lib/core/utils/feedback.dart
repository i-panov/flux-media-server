import 'package:flutter/material.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:fpdart/fpdart.dart';

/// Показ SnackBar-фидбеков.
///
/// Раньше один и тот же `ScaffoldMessenger.of(context).showSnackBar(SnackBar(
/// content: Text('${l.errorLabel}: ${failure.message}'), backgroundColor:
/// Colors.red))` встречался 7 раз, а вариант без подписи ошибки — ещё
/// десяток. Здесь одно место, где решается, как выглядит сообщение.

/// Сообщение об ошибке в формате «Ошибка: <текст>».
void showErrorSnackBar(BuildContext context, String message) {
  showTextSnackBar(
    context,
    '${context.l10n.errorLabel}: $message',
    isError: true,
  );
}

/// Сообщение об ошибке из типизированного [Failure].
void showFailureSnackBar(BuildContext context, Failure failure) =>
    showErrorSnackBar(context, failure.message);

/// Произвольное сообщение.
///
/// Фон: [color] если задан, иначе красный при [isError], иначе тема.
/// Прежний SnackBar скрывается — иначе быстрыеSuccess/failure накладываются.
void showTextSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Color? color,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? (isError ? Colors.red : null),
      ),
    );
}

/// Успешное действие: зелёный фон, принято в UI за «всё прошло».
void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
}

/// Показать ошибку из результата usecase'а, успех проигнорировать.
///
/// Типичный случай: `await deleteMedia(...)` — интересует только фидбек
/// при сбое, ветка успеха обрабатывается отдельно (инвалидация, закрытие
/// диалога).
void showFailureIfAny<T>(BuildContext context, Either<Failure, T> result) {
  result.fold((failure) => showFailureSnackBar(context, failure), (_) {});
}

import 'package:flutter/foundation.dart' show immutable;

/// Base class for all failures in the application.
@immutable
abstract class Failure {
  const new({required this.message});

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Читаемое сообщение вместо `Instance of 'ServerFailure'`.
  ///
  /// `Failure` попадает в `AsyncError` провайдеров как есть (без обёртки
  /// в `Exception`), и UI печатает ошибку через `toString()`. Тип в логах
  /// при этом виден через `runtimeType` — смотрите поле, а не строку.
  @override
  String toString() => message;
}

class ServerFailure extends Failure {
  const new({super.message = 'Server error occurred'});
}

class NetworkFailure extends Failure {
  const new({super.message = 'Network error occurred'});
}

class AuthFailure extends Failure {
  const new({super.message = 'Authentication error occurred'});
}

/// Операция загрузки (upload/download) была отменена пользователем.
class UploadCancelledFailure extends Failure {
  const new({super.message = 'Upload cancelled'});
}

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
  int get hashCode => message.hashCode;
}

class ServerFailure extends Failure {
  const new({super.message = 'Server error occurred'});
}

class NetworkFailure extends Failure {
  const new({super.message = 'Network error occurred'});
}

class CacheFailure extends Failure {
  const new({super.message = 'Cache error occurred'});
}

class AuthFailure extends Failure {
  const new({super.message = 'Authentication error occurred'});
}

/// Операция загрузки (upload/download) была отменена пользователем.
class UploadCancelledFailure extends Failure {
  const new({super.message = 'Upload cancelled'});
}

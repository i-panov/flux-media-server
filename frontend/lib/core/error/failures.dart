import 'package:flutter/foundation.dart' show immutable;

/// Base class for all failures in the application.
@immutable
abstract class Failure {
  const Failure({required this.message});

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
  const ServerFailure({super.message = 'Server error occurred'});
}

class NetworkFailure extends Failure {
  const NetworkFailure({super.message = 'Network error occurred'});
}

class CacheFailure extends Failure {
  const CacheFailure({super.message = 'Cache error occurred'});
}

class AuthFailure extends Failure {
  const AuthFailure({super.message = 'Authentication error occurred'});
}

/// Операция загрузки (upload/download) была отменена пользователем.
class UploadCancelledFailure extends Failure {
  const UploadCancelledFailure({super.message = 'Upload cancelled'});
}

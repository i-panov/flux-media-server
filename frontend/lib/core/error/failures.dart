/// Base class for all failures in the application.
abstract class Failure {
  const Failure({required this.message});

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure && runtimeType == other.runtimeType && message == other.message;

  @override
  int get hashCode => message.hashCode;
}

class ServerFailure extends Failure {
  const ServerFailure({String message = "Server error occurred"})
      : super(message: message);
}

class NetworkFailure extends Failure {
  const NetworkFailure({String message = "Network error occurred"})
      : super(message: message);
}

class CacheFailure extends Failure {
  const CacheFailure({String message = "Cache error occurred"})
      : super(message: message);
}

class AuthFailure extends Failure {
  const AuthFailure({String message = "Authentication error occurred"})
      : super(message: message);
}

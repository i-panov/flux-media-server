import 'dart:developer' as developer;

class AppLogger {
  static void error(String message, [Object? error, StackTrace? stack]) {
    developer.log(
      message,
      name: 'Flux',
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }

  static void warn(String message) {
    developer.log(message, name: 'Flux', level: 900);
  }

  static void info(String message) {
    developer.log(message, name: 'Flux', level: 800);
  }
}

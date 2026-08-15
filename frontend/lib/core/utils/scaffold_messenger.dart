import 'package:flutter/material.dart';

/// Глобальный ключ [ScaffoldMessengerState], подключённый к [MaterialApp].
///
/// Позволяет показывать SnackBar-фидбеки (например, статус скачивания)
/// из любого места приложения без BuildContext-иерархии:
/// `scaffoldMessengerKey.currentState?.showSnackBar(...)`.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

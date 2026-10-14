import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';

/// Версия бэкенда из GET /api/health (поле `version`).
/// Нужна экрану настроек (О приложении): сверка, что правки бэкенда
/// реально применились на сервере. null — сервер недоступен/старый
/// (без поля версии). Без авторизации: health публичный.
/// Ошибки глотаются осознанно: версия — информация, а не блокер.
final backendVersionProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(directHttpClientProvider);
  final baseUrl = ref.watch(baseUrlProvider);
  try {
    final response = await client
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    final version = body['version'];
    if (version is! String || version.isEmpty) return null;
    return version;
  } on Exception catch (e) {
    AppLogger.warn('Backend version check failed: $e');
    return null;
    // jsonDecode на кривом теле кидает Error, а не Exception — версия
    // всё равно необязательна, глотаем и её.
    // ignore: avoid_catching_errors
  } on Error {
    return null;
  }
});

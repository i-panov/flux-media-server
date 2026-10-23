import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Сервис уведомлений о загрузке.
///
/// null — уведомления не инициализированы (например, в тестах или на
/// платформах без поддержки): тогда пачка идёт молча.
final uploadNotificationsProvider = Provider<UploadNotifications?>(
  (ref) => null,
);

/// Уведомление о ходе пакетной загрузки.
///
/// Это единственный экран прогресса вне приложения: ушедшему с экрана
/// загрузки иначе не видно, что загрузка вообще идёт, и нечем её
/// отменить.
///
/// Обновление идёт из пакетного контроллера — он переживает экран,
/// поэтому уведомление живо и без открытого экрана загрузки.
class UploadNotifications {
  new({
    required this.channelId,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// id канала уведомлений: выводится из applicationId, как остальные
  /// каналы приложения.
  final String channelId;

  final FlutterLocalNotificationsPlugin _plugin;

  /// Локаль приложения: строки уведомления должны идти на языке
  /// интерфейса. Задаётся в main, где доступны настройки.
  Locale Function() localeOf = () => const Locale('en');

  /// Свой id, чтобы не спорить с уведомлением плеера.
  static const notificationId = 4201;

  /// Плагин готов принимать уведомления.
  ///
  /// Сбой инициализации оставляет флаг снятым: показ тогда молча
  /// пропускается, а не бросает исключение на каждом файле пачки.
  var _ready = false;

  /// Готовит плагин. [onTap] вызывается при тапе по уведомлению —
  /// обычно это открытие экрана загрузки.
  Future<void> init({DidReceiveNotificationResponseCallback? onTap}) async {
    final l = _l10n();
    const android = AndroidInitializationSettings('app_icon');
    const darwin = DarwinInitializationSettings();
    final linux = LinuxInitializationSettings(
      defaultActionName: l.uploadNotificationOpen,
    );
    const windows = WindowsInitializationSettings(
      appName: 'Flux',
      appUserModelId: 'Flux',
      guid: '6d2c8a0e-1f6b-4b3a-9f5e-6f0a2c9b7d31',
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: linux,
        windows: windows,
      ),
      onDidReceiveNotificationResponse: onTap,
    );
    _ready = true;
  }

  /// Показывает прогресс: [done] из [total], [progress] — доля текущего
  /// файла (null — файл только что начался, точная доля неизвестна).
  Future<void> showProgress({
    required int done,
    required int total,
    double? progress,
  }) async {
    if (!_ready) return;
    final l = _l10n();
    // Имя канала Android запоминает при создании — дальше оно не
    // обновляется, это ограничение системы, а не наше.
    final details = AndroidNotificationDetails(
      channelId,
      l.uploadNotificationChannel,
      channelDescription: l.uploadNotificationChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      silent: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress == null ? 0 : (progress * 100).round(),
      indeterminate: progress == null,
    );
    await _plugin.show(
      id: notificationId,
      title: l.uploadNotificationTitle,
      body: l.uploadNotificationBody(done, total),
      notificationDetails: NotificationDetails(android: details),
    );
  }

  /// Убирает уведомление: пачка закончилась или отменена.
  Future<void> clear() async {
    if (!_ready) return;
    await _plugin.cancel(id: notificationId);
  }

  AppLocalizations _l10n() => lookupAppLocalizations(localeOf());
}

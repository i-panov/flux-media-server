import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/media/presentation/services/upload_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('до инициализации показ и очистка ничего не бросают', () async {
    // Сбой инициализации плагина (нет демона уведомлений, отозвано
    // разрешение) не должен превращаться в исключение на каждом файле
    // пачки — сервис тогда молча пропускает показ.
    final notifications = UploadNotifications(channelId: 'test');

    await expectLater(
      notifications.showProgress(done: 1, total: 2),
      completes,
    );
    await expectLater(notifications.clear(), completes);
  });
}

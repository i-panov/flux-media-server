import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Скачивает обложку трека в файл системного временного каталога.
///
/// Живёт отдельно от `FluxAudioHandler`: сам хендлер не знает про HTTP.
/// Клиент создаётся короткоживущим на каждый вызов и закрывается сразу:
/// общий клиент приложения сюда передавать нельзя — хендлер работает в
/// фоновом изоляте audio_service, а `http.Client` с открытыми сокетами
/// нельзя шарить между изолятами. Заодно это снимает вопрос закрытия:
/// некому «забыть» закрыть долгоживущий клиент.
///
/// Флаг доверия самоподписанному сертификату — снимок на момент создания:
/// обложка не критична, а пробрасывать живые настройки через границу
/// изолята нечем. Худший исход при смене флага — пропущенная картинка
/// в уведомлении до перезапуска.
class ArtworkFileFetcher {
  new({
    required this.trustSelfSigned,
    this.timeout = _defaultTimeout,
    http.Client Function()? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           (() =>
               TimeoutHttpClient(trustSelfSignedCertificates: trustSelfSigned));

  static const _defaultTimeout = Duration(seconds: 10);

  final bool trustSelfSigned;

  /// Таймаут одного скачивания.
  final Duration timeout;

  /// Фабрика клиента: в проде — короткоживущий `TimeoutHttpClient`,
  /// в тестах — `MockClient`.
  final http.Client Function() _clientFactory;

  /// Имя файла обложки для [artUri]: стабильное между запусками, чтобы
  /// старый файл находился стартовой уборкой, а не копился как мусор.
  ///
  /// Хеш — sha256, а не `String.hashCode`: хеш строк в Dart рандомизирован
  /// на каждый запуск, и с ним уборка не нашла бы вчерашние файлы.
  static String fileNameFor(Uri artUri) {
    final digest = sha256.convert(utf8.encode(artUri.toString())).toString();
    return 'flux_art_${artUri.pathSegments.last}_${digest.substring(0, 16)}.jpg';
  }

  /// Возвращает скачанный файл или `null` — обложка не критична, любая
  /// ошибка (сеть, 404, пустое тело) тихо оставляет уведомление без
  /// картинки.
  Future<File?> call(String url, Map<String, String>? httpHeaders) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.scheme.startsWith('http')) return null;

    final client = _clientFactory();
    try {
      final response = await client
          .get(uri, headers: httpHeaders ?? const {})
          .timeout(timeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${fileNameFor(uri)}');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (e) {
      AppLogger.warn('Artwork download failed: $e');
      return null;
    } finally {
      client.close();
    }
  }
}

/// Провайдер загрузчика обложек (для основного изолята; в фоне
/// audio_service экземпляр собирается в `main.dart` со снимком флага).
final artworkFileFetcherProvider = Provider<ArtworkFileFetcher>((ref) {
  final trustSelfSigned = ref.watch(
    settingsProvider.select((s) => s.settings.trustSelfSignedCertificates),
  );
  return ArtworkFileFetcher(trustSelfSigned: trustSelfSigned);
});

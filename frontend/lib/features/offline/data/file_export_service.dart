import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Результат сохранения медиафайла в видимую пользователю область.
sealed class FileExportResult {
  const new();
}

/// Файл сохранён; [destination] — человекочитаемое место
/// (имя файла в Загрузках на Android, полный путь на десктопе).
class FileExportSaved extends FileExportResult {
  const new(this.destination);

  final String destination;
}

/// Пользователь отменил выбор места сохранения.
class FileExportCancelled extends FileExportResult {
  const new();
}

/// Сохранение не удалось; [message] — техническое, поверх него
/// UI кладёт локализованный `fileSaveFailed`.
class FileExportFailed extends FileExportResult {
  const new(this.message);

  final String message;
}

/// Имя файла для сохранения: оригинальное с сервера, в крайнем случае
/// санитизированный заголовок с расширением из оригинала.
@visibleForTesting
String exportFileNameFor(Media media) {
  final raw = media.filename.trim();
  // Хвостовой слэш («abc/») даёт пустой last — такие сегменты
  // пропускаем, иначе дальше уедёт пустое имя в bad_args.
  final segments = raw.split('/').where((s) => s.trim().isNotEmpty).toList();
  if (segments.isNotEmpty) return segments.last;
  final ext = _extensionOf(raw);
  final safe = media.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final base = safe.isEmpty ? 'media_${media.id}' : safe;
  return '$base$ext';
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  final ext = name.substring(dot);
  return RegExp(r'^\.[A-Za-z0-9]{1,5}$').hasMatch(ext) ? ext : '';
}

/// MIME по расширению для системного диалога сохранения и MediaStore.
/// Полный справочник не нужен: неверный тип влияет только на подпись
/// в проводнике, сами байты всегда корректны (копия из кеша).
@visibleForTesting
String mimeTypeForFileName(String fileName) {
  final ext = _extensionOf(fileName).toLowerCase().replaceFirst('.', '');
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'ogg' => 'audio/ogg',
    'opus' => 'audio/opus',
    'flac' => 'audio/flac',
    'wav' => 'audio/wav',
    'mp4' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'avi' => 'video/x-msvideo',
    'mov' => 'video/quicktime',
    _ => 'application/octet-stream',
  };
}

/// Платформенное сохранение готового файла из кеша.
///
/// Разделено именно так, а не через `FilePicker.saveFile`: тот требует
/// все байты в памяти ([Uint8List]) — гигабайтное видео уронило бы
/// приложение. Здесь везде потоковое копирование без загрузки в память:
///
/// - Android: системные Загрузки через MediaStore (API 29+) или прямой
///   путь в Загрузки (старше), запись — нативным кодом в MainActivity;
/// - остальные платформы: пользователь выбирает папку, копирует Dart.
abstract class FileSaver {
  Future<String?> saveCachedFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  });
}

/// Сохранение через нативный канал (`<applicationId>/files`).
///
/// Канал может отсутствовать (тесты, десктоп): тогда бросаем
/// [FileExportFailed] ещё до вызова, а не падаем на MissingPluginException
/// в середине флоу.
class MethodChannelFileSaver implements FileSaver {
  new({required String channelName}) : _channel = MethodChannel(channelName);

  final MethodChannel _channel;

  @override
  Future<String?> saveCachedFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });
    } on MissingPluginException {
      throw const FileSaverUnavailable();
    }
  }
}

/// Канал недоступен: не Android или хендлер не зарегистрирован.
class FileSaverUnavailable implements Exception {
  const new();

  @override
  String toString() => 'FileSaverUnavailable';
}

/// Платформа не поддерживается: iOS (песочница запрещает прямую запись,
/// нужен отдельный нативный сейвер) и web (некуда копировать).
class FileSaverUnsupported implements Exception {
  const new();

  @override
  String toString() => 'FileSaverUnsupported';
}

/// Заглушка для неподдерживаемых платформ: бросает сразу, а не молчит
/// «отменой» (как было бы с getDirectoryPath → null на iOS).
class UnsupportedFileSaver implements FileSaver {
  const new();

  @override
  Future<String?> saveCachedFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) => throw const FileSaverUnsupported();
}

/// Фолбэк для десктопа: выбор папки через file_picker + `File.copy`.
///
/// На Android не используется: scoped storage запрещает прямую запись
/// в общие папки, там только [MethodChannelFileSaver].
class DirectoryPickerFileSaver implements FileSaver {
  new({Future<String?> Function()? pickDirectory})
    : _pickDirectory = pickDirectory ?? FilePicker.getDirectoryPath;

  final Future<String?> Function() _pickDirectory;

  @override
  Future<String?> saveCachedFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    final dir = await _pickDirectory();
    if (dir == null) return null;
    final target = File('$dir/$fileName');
    await File(sourcePath).copy(target.path);
    return target.path;
  }
}

/// Оркестрация «Скачать»: гарантия кеша + платформенное сохранение.
///
/// Обратного доверия нет: чужой файл из пользовательской области никогда
/// не попадает в кеш — поток всегда кеш → наружу.
///
/// Зависимости — колбэками, а не провайдерами: сервис тестируется
/// фейками без path_provider и контейнера.
class FileExportService {
  new({
    required Future<String?> Function(Media media) ensureCached,
    required FileSaver fileSaver,
    // Поля приватные (_ensureCached), а параметры обязаны быть публичными
    // (ensureCached): иначе внешний код не соберёт сервис с колбэками.
    // ignore: prefer_initializing_formals
  }) : _ensureCached = ensureCached,
       // Поле приватное (_fileSaver), параметр обязан быть публичным
       // (fileSaver): иначе внешний код не соберёт сервис с колбэками.
       // ignore: prefer_initializing_formals
       _fileSaver = fileSaver;

  final Future<String?> Function(Media media) _ensureCached;
  final FileSaver _fileSaver;

  Future<FileExportResult> exportMedia(Media media) async {
    final cachedPath = await _ensureCached(media);
    if (cachedPath == null) {
      return const FileExportFailed('cache unavailable');
    }
    final fileName = exportFileNameFor(media);
    try {
      final destination = await _fileSaver.saveCachedFile(
        sourcePath: cachedPath,
        fileName: fileName,
        mimeType: mimeTypeForFileName(fileName),
      );
      if (destination == null) return const FileExportCancelled();
      return FileExportSaved(destination);
    } on FileSaverUnavailable {
      rethrow;
    } on FileSaverUnsupported {
      rethrow;
    } catch (e) {
      AppLogger.error('File export failed', e);
      return FileExportFailed(e.toString());
    }
  }
}

/// Имя нативного канала сохранения: тот же вывод из applicationId,
/// что и у уведомлений (`main.dart` + `MainActivity.kt`). Задаётся из
/// `main()` до `runApp`; без него на Android используется фолбэк
/// выбора папки (как на десктопе).
String? _fileChannelName;

/// Задать имя канала сохранения. Вызывается один раз из `main()`.
void setFileChannelName(String name) {
  _fileChannelName = name;
}

/// Выбор реализации: на Android — системные Загрузки через нативный код
/// (scoped storage запрещает прямую запись), на десктопе — папка + копия.
/// iOS и web не поддерживаются ([UnsupportedFileSaver] с явной ошибкой,
/// а не молчанием).
final fileSaverProvider = Provider<FileSaver>((ref) {
  if (kIsWeb || Platform.isIOS) return const UnsupportedFileSaver();
  final channel = _fileChannelName;
  if (Platform.isAndroid && channel != null) {
    return MethodChannelFileSaver(channelName: channel);
  }
  return DirectoryPickerFileSaver();
});

/// Оркестрация с реальной гарантией кеша: сначала смотрим готовый файл,
/// иначе качаем через общий нотифаер (прогресс виден на иконке ряда),
/// затем платформенное сохранение.
final fileExportServiceProvider = Provider<FileExportService>((ref) {
  return FileExportService(
    ensureCached: (media) async {
      final cache = ref.read(offlineCacheServiceProvider);
      final existing = await cache.getLocalPath(media.id);
      if (existing != null) return existing;
      await ref.read(downloadsStateProvider.notifier).download(media);
      return await cache.getLocalPath(media.id);
    },
    fileSaver: ref.watch(fileSaverProvider),
  );
});

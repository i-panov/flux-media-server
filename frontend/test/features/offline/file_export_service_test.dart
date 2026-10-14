import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/offline/data/file_export_service.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _media({int id = 1, String title = 'Трек', String filename = ''}) =>
    Media(
      id: id,
      title: title,
      type: MediaType.audio,
      fileSize: 1024,
      filename: filename,
    );

/// Фейк сейвера: записывает вызовы, результат задаётся заранее.
class _FakeSaver implements FileSaver {
  String? savedSource;
  String? savedName;
  String? savedMime;
  String? result = '/dest/file.mp3';
  Exception? error;

  @override
  Future<String?> saveCachedFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    savedSource = sourcePath;
    savedName = fileName;
    savedMime = mimeType;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  group('exportFileNameFor', () {
    test('берёт оригинальное имя с сервера', () {
      expect(
        exportFileNameFor(_media(filename: 'artist - song.flac')),
        'artist - song.flac',
      );
    });

    test('отрезает путь, оставляя базовое имя', () {
      expect(
        exportFileNameFor(_media(filename: 'season1/episode2.mkv')),
        'episode2.mkv',
      );
    });

    test('пустое имя: санитизированный заголовок + расширение', () {
      expect(
        exportFileNameFor(_media(title: 'Фильм: часть 1/2')),
        'Фильм_ часть 1_2',
      );
    });

    test('пустые имя и заголовок: media_<id>', () {
      expect(exportFileNameFor(_media(id: 7, title: '  ')), 'media_7');
    });

    test('хвостовой слэш: пустой сегмент пропускается', () {
      expect(exportFileNameFor(_media(filename: 'abc/')), 'abc');
      expect(exportFileNameFor(_media(filename: 'dir/subdir/')), 'subdir');
      expect(
        exportFileNameFor(_media(title: '  ', filename: '///')),
        'media_1',
      );
    });
  });

  group('mimeTypeForFileName', () {
    test('аудио и видео по расширению', () {
      expect(mimeTypeForFileName('a.mp3'), 'audio/mpeg');
      expect(mimeTypeForFileName('a.flac'), 'audio/flac');
      expect(mimeTypeForFileName('v.mkv'), 'video/x-matroska');
      expect(mimeTypeForFileName('v.mp4'), 'video/mp4');
    });

    test('регистр расширения не важен, неизвестное — octet-stream', () {
      expect(mimeTypeForFileName('V.MP4'), 'video/mp4');
      expect(mimeTypeForFileName('a.xyz'), 'application/octet-stream');
      expect(mimeTypeForFileName('noext'), 'application/octet-stream');
    });
  });

  group('FileExportService', () {
    test('готовый кеш: сеть не трогаем, копируем сразу', () async {
      final saver = _FakeSaver();
      var ensured = 0;
      final service = FileExportService(
        ensureCached: (_) async {
          ensured++;
          return '/cache/flux_media_1';
        },
        fileSaver: saver,
      );
      final result = await service.exportMedia(_media(filename: 'song.mp3'));
      expect(result, isA<FileExportSaved>());
      expect((result as FileExportSaved).destination, '/dest/file.mp3');
      expect(ensured, 1);
      expect(saver.savedSource, '/cache/flux_media_1');
      expect(saver.savedName, 'song.mp3');
      expect(saver.savedMime, 'audio/mpeg');
    });

    test('нет кеша: FileExportFailed, сейвер не вызывается', () async {
      final saver = _FakeSaver();
      final service = FileExportService(
        ensureCached: (_) async => null,
        fileSaver: saver,
      );
      final result = await service.exportMedia(_media());
      expect(result, isA<FileExportFailed>());
      expect(saver.savedSource, isNull);
    });

    test('отмена диалога: FileExportCancelled', () async {
      final saver = _FakeSaver()..result = null;
      final service = FileExportService(
        ensureCached: (_) async => '/cache/f',
        fileSaver: saver,
      );
      expect(await service.exportMedia(_media()), isA<FileExportCancelled>());
    });

    test('ошибка записи: FileExportFailed с текстом', () async {
      final saver = _FakeSaver()..error = Exception('denied');
      final service = FileExportService(
        ensureCached: (_) async => '/cache/f',
        fileSaver: saver,
      );
      final result = await service.exportMedia(_media());
      expect(result, isA<FileExportFailed>());
      expect((result as FileExportFailed).message, contains('denied'));
    });

    test('недоступный канал пробрасывается, а не глотается', () async {
      final saver = _FakeSaver()..error = const FileSaverUnavailable();
      final service = FileExportService(
        ensureCached: (_) async => '/cache/f',
        fileSaver: saver,
      );
      await expectLater(
        service.exportMedia(_media()),
        throwsA(isA<FileSaverUnavailable>()),
      );
    });

    test('неподдерживаемая платформа пробрасывается так же', () async {
      final service = FileExportService(
        ensureCached: (_) async => '/cache/f',
        fileSaver: const UnsupportedFileSaver(),
      );
      await expectLater(
        service.exportMedia(_media()),
        throwsA(isA<FileSaverUnsupported>()),
      );
    });
  });

  group('DirectoryPickerFileSaver', () {
    test('отмена выбора папки возвращает null', () async {
      final saver = DirectoryPickerFileSaver(pickDirectory: () async => null);
      expect(
        await saver.saveCachedFile(
          sourcePath: '/cache/f',
          fileName: 'a.mp3',
          mimeType: 'audio/mpeg',
        ),
        isNull,
      );
    });
  });
}

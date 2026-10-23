import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_source.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/batch_upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/screens/upload_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/upload_source_helpers.dart';

/// Репозиторий, у которого любая загрузка завершается сразу: тесту нужен
/// только факт «пачка отработала», содержимое не важно.
class _FakeMediaRepository implements MediaRepository {
  @override
  Future<
    Either<Failure, ({bool exists, int? mediaId, String? title, bool trashed})>
  >
  checkHash(String hash) async =>
      const Right((exists: false, mediaId: null, title: null, trashed: false));

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required UploadSource source,
    required int length,
    required String mediaType,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async => Right(UploadResult(jobId: source.path.hashCode));

  @override
  Future<Either<Failure, UploadStatus>> getUploadStatus(int jobId) async =>
      Right(
        UploadStatus(
          id: jobId,
          status: 'done',
          // Медиа с id: только с ним видно, кладёт ли экран файл
          // в выбранную коллекцию.
          media: const Media(
            id: 42,
            title: 'File',
            type: MediaType.video,
            fileSize: 1024,
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Подмена системного пикера: тест сам решает, что выбрал пользователь.
final class _FakeFilePicker extends FilePickerPlatform {
  new(this.files);

  final List<PlatformFile> files;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

/// Выбранный файл: экран берёт из него имя и путь, содержимое ему не нужно.
final class _FakePlatformFile extends PlatformFile {
  new(this.uri) : name = uri.pathSegments.last;

  @override
  final Uri uri;

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchUploadItem _item(String name) =>
    BatchUploadItem(source: fakeUploadSource(name: name), fileSize: 1024);

Collection _collection(int id, String name, MediaType type) => Collection(
  id: id,
  userId: 7,
  name: name,
  type: type,
  createdAt: DateTime.utc(2024),
  updatedAt: DateTime.utc(2024),
);

void main() {
  ProviderContainer makeContainer(FakeCollectionsRepository collections) {
    collections.onAddItem ??= (collectionId, mediaId) async => Right(
      CollectionItem(id: 1, collectionId: collectionId, mediaId: mediaId),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository()),
        collectionsRepositoryProvider.overrideWithValue(collections),
      ],
    );
    addTearDown(container.dispose);
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-${source.path}';
    return container;
  }

  /// Готовит реальный файл и отдаёт его системному пикеру: экран читает
  /// размер именно с диска, поэтому заглушка тут не подходит.
  Future<void> passToPicker(String name) async {
    final previous = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final dir = Directory.systemTemp.createTempSync('flux_upload_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/$name')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    FilePickerPlatform.instance = _FakeFilePicker([
      _FakePlatformFile(file.uri),
    ]);
  }

  /// Даёт реальному чтению размеров завершиться: без
  /// [WidgetTester.runAsync] оно не идёт (пикер вернулся, размеры висят).
  Future<void> waitForSizes(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    for (var i = 0; i < 20; i++) {
      if (!container.read(batchUploadControllerProvider).sizesPending) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('после аудио-пачки видео-экран предлагает видеоколлекции', (
    tester,
  ) async {
    // Пачка переживает экран, поэтому тип прошлого прогона остаётся в
    // контроллере. Экран другого типа обязан начать с чистого листа:
    // иначе выбор коллекции для новых видеофайлов шёл бы по аудио-типу,
    // и сервер принял бы видео в аудиоколлекцию.
    final collections = FakeCollectionsRepository()
      ..onGetCollections = () async => Right([
        _collection(1, 'Audio collection', MediaType.audio),
        _collection(2, 'Video collection', MediaType.video),
      ]);
    final container = makeContainer(collections);
    final batch = container.read(batchUploadControllerProvider.notifier);

    // Выбор файлов экраном (после нативного пикера).
    void selectFiles(String name) => batch.setFiles([_item(name)]);

    selectFiles('a.mp3');
    await tester.runAsync(() => batch.startAll(mediaType: 'audio'));
    expect(batch.mediaType, 'audio');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UploadScreen(mediaType: 'video'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    selectFiles('b.mp4');
    await tester.pumpAndSettle();

    await tester.tap(find.text('No Collection'));
    await tester.pumpAndSettle();

    expect(find.text('Video collection'), findsOneWidget);
    expect(find.text('Audio collection'), findsNothing);
  });

  testWidgets('выбор файлов другого типа сбрасывает коллекцию пачки', (
    tester,
  ) async {
    // Cross-type: экран видео открыт, пока идёт аудио-пачка, поэтому
    // сброс при входе не срабатывает (clear выходит при isRunning), и
    // picker фильтрует коллекции по типу пачки — предлагает аудио.
    // Такой выбор не должен пережить выбор видеофайлов: сервер тип пары
    // «медиа — коллекция» не сверяет, и видео ушло бы в аудиоколлекцию.
    final collections = FakeCollectionsRepository()
      ..onGetCollections = () async => Right([
        _collection(1, 'Audio collection', MediaType.audio),
        _collection(2, 'Video collection', MediaType.video),
      ]);
    final container = makeContainer(collections);
    final batch = container.read(batchUploadControllerProvider.notifier);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UploadScreen(mediaType: 'video'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    batch.setFiles([_item('a.mp3')]);
    await tester.runAsync(() => batch.startAll(mediaType: 'audio'));
    await tester.pumpAndSettle();
    expect(batch.mediaType, 'audio');

    // Пользователь кладёт аудио-пачку в аудиоколлекцию.
    await tester.tap(find.text('No Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio collection'));
    await tester.pumpAndSettle();
    expect(find.text('Collection: Audio collection'), findsOneWidget);

    // Затем выбирает видеофайлы: коллекция чужого типа к ним не относится.
    await passToPicker('b.mp4');
    await tester.tap(find.text('1 files selected'));
    await waitForSizes(tester, container);
    expect(container.read(batchUploadControllerProvider).sizesPending, isFalse);

    expect(find.text('No Collection'), findsOneWidget);
    expect(find.text('Collection: Audio collection'), findsNothing);

    // И загрузка идёт без коллекции: видео в аудиоколлекцию не попадает.
    await tester.tap(find.text('Upload'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(container.read(batchUploadControllerProvider).doneCount, 1);
    expect(collections.addItemCalls, isEmpty);
  });
}

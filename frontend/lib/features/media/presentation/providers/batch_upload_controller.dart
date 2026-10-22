import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';

/// Статус одного файла в пакетной загрузке.
enum BatchItemStatus { pending, active, done, duplicate, failed, cancelled }

/// Один файл пакетной загрузки.
class BatchUploadItem {
  const new({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.status = BatchItemStatus.pending,
    this.errorMessage,
    this.existingTitle,
  });

  final String filePath;
  final String fileName;
  final int fileSize;
  final BatchItemStatus status;
  final String? errorMessage;

  /// Название совпавшего дубликата с сервера (checkHash его отдаёт).
  final String? existingTitle;

  BatchUploadItem copyWith({
    BatchItemStatus? status,
    String? errorMessage,
    String? existingTitle,
    int? fileSize,
  }) {
    return BatchUploadItem(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      errorMessage: errorMessage,
      existingTitle: existingTitle ?? this.existingTitle,
    );
  }
}

/// Состояние пакетной загрузки: список файлов и флаг работы.
class BatchUploadState {
  const new({
    this.items = const [],
    this.isRunning = false,
    this.hashingTotal = 0,
    this.hashingDone = 0,
    this.sizesPending = false,
  });

  final List<BatchUploadItem> items;
  final bool isRunning;

  /// Прогресс фазы хэширования (0/0 — не идёт).
  final int hashingTotal;
  final int hashingDone;

  /// Размеры файлов ещё догружаются. Ноль в fileSize в этот момент —
  /// «не измерено», а не пустой файл; старт заблокирован, иначе быстрый
  /// тап отправил бы 0 в контроллер и получил backstop «empty file».
  final bool sizesPending;

  bool get isHashing => hashingDone < hashingTotal;

  int get doneCount =>
      items.where((i) => i.status == BatchItemStatus.done).length;
  int get duplicateCount =>
      items.where((i) => i.status == BatchItemStatus.duplicate).length;
  int get failedCount =>
      items.where((i) => i.status == BatchItemStatus.failed).length;
}

/// Пакетная загрузка: файлы идут строго последовательно через общий
/// [UploadController] (один активный аплоад — предсказуемый прогресс
/// и та же семантика отмены/дедупа, что у одиночной).
/// Сбой одного файла не останавливает пачку: итог — сводкой в конце.
class BatchUploadController extends Notifier<BatchUploadState> {
  @override
  BatchUploadState build() {
    ref.onDispose(() => _disposed = true);
    return const BatchUploadState();
  }

  bool _cancelled = false;
  bool _disposed = false;

  UploadController get _single => ref.read(uploadControllerProvider.notifier);

  void setFiles(List<BatchUploadItem> items, {bool sizesPending = false}) {
    if (state.isRunning) return;
    state = BatchUploadState(
      items: List.unmodifiable(items),
      sizesPending: sizesPending,
    );
  }

  /// Догрузка размеров после мгновенного показа списка (0 → реальный).
  void updateSizes(Map<String, int> sizesByPath) {
    if (_disposed || state.isRunning) return;
    state = BatchUploadState(
      items: [
        for (final item in state.items)
          if (sizesByPath[item.filePath] case final int size)
            item.copyWith(fileSize: size)
          else
            item,
      ],
    );
  }

  void clear() {
    if (state.isRunning) return;
    state = const BatchUploadState();
  }

  /// Грузит все pending-файлы по очереди. Возвращает сводку для снекбара.
  /// [mediaType] — общий для пачки (экран один на аудио/видео).
  ///
  /// [onUploaded] — вызывается с id каждого загруженного файла: экран
  /// кладёт файл в выбранную коллекцию. Само знание о коллекциях в
  /// контроллере не нужно — это забота вызывающего.
  ///
  /// Хэши считаются пулом ВПЕРЁД, а заливка стартует по готовности
  /// хэша очередного файла — не ждёт весь пул (иначе сезон из 20 серий
  /// сначала целиком хэшируется, и только потом начинается передача).
  Future<BatchUploadState> startAll({
    required String mediaType,
    Future<void> Function(int mediaId)? onUploaded,
  }) async {
    if (state.isRunning || state.items.isEmpty) return state;
    _cancelled = false;
    // Держим одиночный контроллер живым всю пачку: без подписки
    // autoDispose снёс бы его между файлами, и чтение errorMessage
    // после start() вернуло бы свежий idle (ложный «дубликат»).
    final keepAlive = ref.listen<UploadState>(
      uploadControllerProvider,
      (_, _) {},
    );
    state = BatchUploadState(items: state.items, isRunning: true);
    try {
      final hashes = _hashPending();
      for (var i = 0; i < state.items.length; i++) {
        if (_cancelled || _disposed) break;
        final item = state.items[i];
        if (item.status != BatchItemStatus.pending) continue;
        // Хэш именно этого файла — пул уже мог посчитать его давно.
        final hash = await hashes[i];
        if (_cancelled || _disposed) break;
        _setStatus(i, BatchItemStatus.active);
        await _uploadOne(i, item, mediaType, hash, onUploaded);
        if (_cancelled || _disposed) break;
      }
      // Дожимаем оставшиеся хэши, чтобы не текли за пределы пачки.
      await hashes.done;
    } finally {
      keepAlive.close();
      if (!_disposed) {
        // Остаток pending после отмены — тоже отмена: иначе список
        // врёт «ожидают», хотя пачка остановлена пользователем.
        state = BatchUploadState(
          items: [
            for (final item in state.items)
              if (item.status == BatchItemStatus.pending && _cancelled)
                item.copyWith(status: BatchItemStatus.cancelled)
              else
                item,
          ],
        );
      }
    }
    return state;
  }

  /// Параллельный просчёт хэшей pending-файлов (пул 3: больше стримов
  /// с одного диска выигрыша не дают, а память и отмену усложняют).
  /// Возвращает карту готовностей: заливка ждёт свой хэш, не дожидаясь
  /// остальных. null — хэш не посчитался (отмена/ошибка чтения):
  /// _uploadOne тогда считает сам через start (там же проверка отмены).
  _HashPool _hashPending() {
    final indices = [
      for (var i = 0; i < state.items.length; i++)
        if (state.items[i].status == BatchItemStatus.pending) i,
    ];
    _setHashing(total: indices.length, done: 0);
    final pool = _HashPool(indices);
    var cursor = 0;
    Future<void> worker() async {
      while (!_cancelled && !_disposed) {
        if (cursor >= indices.length) return;
        final i = cursor++;
        final item = state.items[i];
        String? hash;
        try {
          hash = await _single.hasher(
            item.filePath,
            () => _cancelled || _disposed,
          );
        } catch (e) {
          AppLogger.error('Batch hash failed', e);
        }
        pool.complete(i, hash);
        _setHashing(total: indices.length, done: pool.completedCount);
      }
    }

    final workers = Future.wait([
      for (var w = 0; w < 3 && w < indices.length; w++) worker(),
    ]);
    pool.done = workers;
    return pool;
  }

  void _setHashing({required int total, required int done}) {
    if (_disposed) return;
    state = BatchUploadState(
      items: state.items,
      isRunning: true,
      hashingTotal: total,
      hashingDone: done,
    );
  }

  /// Отмена: текущий файл — через одиночный контроллер (там же
  /// отменяется и серверная джоба), остаток помечается в finally.
  void cancelAll() {
    _cancelled = true;
    _single.cancel();
  }

  /// Повтор упавших без перепick'а файлов: failed → pending и прогон.
  /// Дубликаты и done не трогаем — их повторять незачем.
  Future<BatchUploadState> retryFailed({
    required String mediaType,
    Future<void> Function(int mediaId)? onUploaded,
  }) async {
    if (state.isRunning) return state;
    state = BatchUploadState(
      items: [
        for (final item in state.items)
          if (item.status == BatchItemStatus.failed)
            item.copyWith(status: BatchItemStatus.pending)
          else
            item,
      ],
    );
    return await startAll(mediaType: mediaType, onUploaded: onUploaded);
  }

  Future<void> _uploadOne(
    int index,
    BatchUploadItem item,
    String mediaType,
    String? knownHash,
    Future<void> Function(int mediaId)? onUploaded,
  ) async {
    var ok = false;
    String? duplicateTitle;
    try {
      ok = await _single.start(
        filePath: item.filePath,
        mediaType: mediaType,
        fileName: item.fileName,
        fileSize: item.fileSize,
        knownHash: knownHash,
        onDuplicateTitle: (title) => duplicateTitle = title,
        // Без pop экрана: пачка продолжается. Списки обновляем теми же
        // провайдерами, что refreshMediaLists, но напрямую: ref нотифаера —
        // Ref, а не WidgetRef, в сигнатуру он не входит.
        onSuccess: (mediaId) async {
          ref
            ..invalidate(mediaListProvider('video'))
            ..invalidate(mediaListProvider('audio'));
          if (mediaId != null) await onUploaded?.call(mediaId);
        },
      );
    } catch (e, st) {
      AppLogger.error('Batch upload item failed', e, st);
      if (!_disposed) _setStatus(index, BatchItemStatus.failed, '$e');
      return;
    }
    if (_disposed) return;
    if (_cancelled) {
      _setStatus(index, BatchItemStatus.cancelled);
      return;
    }
    if (ok) {
      _setStatus(index, BatchItemStatus.done);
      return;
    }
    final single = ref.read(uploadControllerProvider);
    if (single.errorMessage != null) {
      _setStatus(index, BatchItemStatus.failed, single.errorMessage);
    } else {
      // false без ошибки — дубликат (инвариант UploadState.errorMessage).
      _setStatus(index, BatchItemStatus.duplicate, null, duplicateTitle);
    }
  }

  void _setStatus(
    int index,
    BatchItemStatus status, [
    String? error,
    String? existingTitle,
  ]) {
    if (_disposed) return;
    final items = List<BatchUploadItem>.from(state.items);
    items[index] = items[index].copyWith(
      status: status,
      errorMessage: error,
      existingTitle: existingTitle,
    );
    state = BatchUploadState(items: items, isRunning: true);
  }
}

/// Провайдер пакетной загрузки. autoDispose: состояние — состояние
/// экрана; уход гасит цикл (серверные джобы при этом живут дальше,
/// как и у одиночной — семантика та же).
final batchUploadControllerProvider =
    NotifierProvider.autoDispose<BatchUploadController, BatchUploadState>(
      BatchUploadController.new,
    );

/// Готовности хэшей пачки: каждый индекс получает свой Future, заливка
/// ждёт только его. Пустая карта завершений при отмене — ожидающие
/// получают null (тогда хэшер досчитает внутри start).
class _HashPool {
  new(this.indices) {
    for (final i in indices) {
      _waiters[i] = Completer<String?>();
    }
  }

  final List<int> indices;
  final Map<int, Completer<String?>> _waiters = {};
  Future<void> done = Future.value();
  int completedCount = 0;

  Future<String?> operator [](int index) =>
      _waiters[index]?.future ?? Future.value();

  void complete(int index, String? hash) {
    final waiter = _waiters[index];
    if (waiter == null || waiter.isCompleted) return;
    completedCount++;
    waiter.complete(hash);
  }
}

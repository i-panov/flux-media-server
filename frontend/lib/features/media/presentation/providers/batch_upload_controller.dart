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
  });

  final String filePath;
  final String fileName;
  final int fileSize;
  final BatchItemStatus status;
  final String? errorMessage;

  BatchUploadItem copyWith({BatchItemStatus? status, String? errorMessage}) {
    return BatchUploadItem(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}

/// Состояние пакетной загрузки: список файлов и флаг работы.
class BatchUploadState {
  const new({this.items = const [], this.isRunning = false});

  final List<BatchUploadItem> items;
  final bool isRunning;

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

  UploadController get _single =>
      ref.read(uploadControllerProvider.notifier);

  void setFiles(List<BatchUploadItem> items) {
    if (state.isRunning) return;
    state = BatchUploadState(items: List.unmodifiable(items));
  }

  void clear() {
    if (state.isRunning) return;
    state = const BatchUploadState();
  }

  /// Грузит все pending-файлы по очереди. Возвращает сводку для снекбара.
  /// [mediaType] — общий для пачки (экран один на аудио/видео).
  Future<BatchUploadState> startAll({required String mediaType}) async {
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
      for (var i = 0; i < state.items.length; i++) {
        if (_cancelled || _disposed) break;
        final item = state.items[i];
        if (item.status != BatchItemStatus.pending) continue;
        _setStatus(i, BatchItemStatus.active);
        await _uploadOne(i, item, mediaType);
        if (_cancelled || _disposed) break;
      }
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

  /// Отмена: текущий файл — через одиночный контроллер (там же
  /// отменяется и серверная джоба), остаток помечается в finally.
  void cancelAll() {
    _cancelled = true;
    _single.cancel();
  }

  /// Повтор упавших без перепick'а файлов: failed → pending и прогон.
  /// Дубликаты и done не трогаем — их повторять незачем.
  Future<BatchUploadState> retryFailed({required String mediaType}) async {
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
    return await startAll(mediaType: mediaType);
  }

  Future<void> _uploadOne(int index, BatchUploadItem item, String mediaType) async {
    var ok = false;
    try {
      ok = await _single.start(
        filePath: item.filePath,
        mediaType: mediaType,
        fileName: item.fileName,
        fileSize: item.fileSize,
        // Без pop экрана: пачка продолжается. Списки обновляем теми же
        // провайдерами, что refreshMediaLists, но напрямую: ref нотифаера —
        // Ref, а не WidgetRef, в сигнатуру он не входит.
        onSuccess: () async {
          ref
            ..invalidate(mediaListProvider('video'))
            ..invalidate(mediaListProvider('audio'));
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
      _setStatus(index, BatchItemStatus.duplicate);
    }
  }

  void _setStatus(int index, BatchItemStatus status, [String? error]) {
    if (_disposed) return;
    final items = List<BatchUploadItem>.from(state.items);
    items[index] = items[index].copyWith(status: status, errorMessage: error);
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

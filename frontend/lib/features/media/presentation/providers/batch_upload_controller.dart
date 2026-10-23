import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/domain/models/upload_source.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/services/upload_notifications.dart';

/// Статус одного файла в пакетной загрузке.
enum BatchItemStatus { pending, active, done, duplicate, failed, cancelled }

/// Один файл пакетной загрузки.
class BatchUploadItem {
  const new({
    required this.source,
    required this.fileSize,
    this.status = BatchItemStatus.pending,
    this.errorMessage,
    this.existingTitle,
  });

  /// Источник файла: имя и поток с содержимым.
  final UploadSource source;

  /// Размер в байтах; 0 — размер ещё не измерен.
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
      source: source,
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

  int get pendingCount =>
      items.where((i) => i.status == BatchItemStatus.pending).length;
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

  /// Тип медиа текущей пачки ('video'/'audio'): по нему тап по уведомлению
  /// открывает нужный экран загрузки.
  String? _mediaType;

  /// Тип медиа идущей пачки (null — пачка не идёт).
  String? get mediaType => _mediaType;

  /// Коллекция, в которую складываются загруженные файлы (null — никуда).
  int? _collectionId;

  /// Сколько файлов не удалось положить в коллекцию за текущий прогон.
  int _collectionFailures = 0;

  /// Ошибки добавления в коллекцию: экран показывает их в сводке.
  int get collectionFailures => _collectionFailures;

  /// Момент последнего обновления уведомления — для дросселя.
  DateTime _lastNotificationUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  UploadController get _single => ref.read(uploadControllerProvider.notifier);

  void setFiles(List<BatchUploadItem> items, {bool sizesPending = false}) {
    if (state.isRunning) return;
    // Новый набор — новая пачка, и тип/коллекция прошлой к ней не
    // относятся. Экран другого типа, открытый во время чужой пачки,
    // иначе выбрал бы коллекцию по типу остатков старой (видеофайлы
    // легли бы в аудиоколлекцию), а повтор ушёл бы чужим media_type.
    _forgetBatch();
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
          if (sizesByPath[item.source.path] case final int size)
            item.copyWith(fileSize: size)
          else
            item,
      ],
    );
  }

  void clear() {
    if (state.isRunning) return;
    // Тип и коллекция уходят вместе с файлами: экран, открытый после
    // пачки другого типа, иначе фильтровал бы коллекции по типу уже
    // стёртой пачки и принял бы новый набор за её продолжение.
    _forgetBatch();
    state = const BatchUploadState();
  }

  /// Забывает тип и коллекцию прошлой пачки: они описывают набор файлов,
  /// которого больше нет.
  void _forgetBatch() {
    _mediaType = null;
    _collectionId = null;
  }

  /// Грузит все pending-файлы по очереди. Возвращает сводку для снекбара.
  /// [mediaType] — общий для пачки (экран один на аудио/видео).
  ///
  /// [collectionId] — коллекция, в которую после успеха кладётся каждый
  /// файл. Работает именно здесь, а не колбэком экрана: пачка переживает
  /// экран, а `ref` закрытого экрана бросает StateError — успешно
  /// залитый файл тогда пометился бы упавшим, а добавление в коллекцию
  /// потерялось бы.
  ///
  /// Хэши считаются пулом ВПЕРЁД, а заливка стартует по готовности
  /// хэша очередного файла — не ждёт весь пул (иначе сезон из 20 серий
  /// сначала целиком хэшируется, и только потом начинается передача).
  Future<BatchUploadState> startAll({
    required String mediaType,
    int? collectionId,
  }) async {
    if (state.isRunning || state.items.isEmpty) return state;
    // Грузить нечего — выход ДО смены типа и коллекции пачки. Иначе экран
    // другого типа, нажав «Загрузить» по чужой завершённой пачке,
    // переписал бы её тип: последующий повтор ушёл бы на сервер с чужим
    // media_type, а коллекция — из чужого экрана.
    if (state.pendingCount == 0) return state;
    _cancelled = false;
    _mediaType = mediaType;
    _collectionId = collectionId;
    _collectionFailures = 0;
    // Держим одиночный контроллер живым всю пачку: без подписки
    // autoDispose снёс бы его между файлами, и чтение errorMessage
    // после start() вернуло бы свежий idle (ложный «дубликат»).
    final keepAlive = ref.listen<UploadState>(uploadControllerProvider, (
      previous,
      next,
    ) {
      // Прогресс текущего файла в уведомлении: без него на одном
      // большом файле видно только «1 из 1» — а это и есть долгий
      // момент. Обновления дросселируются: контроллер загрузки
      // отдаёт прогресс пачками по 150 мс, в шторку так часто нельзя.
      _updateNotification(
        done: state.doneCount,
        total: state.items.length,
        progress: next.progress,
      );
    });
    state = BatchUploadState(items: state.items, isRunning: true);
    try {
      await _showNotification(done: 0, total: state.items.length);
      final hashes = _hashPending();
      for (var i = 0; i < state.items.length; i++) {
        if (_cancelled || _disposed) break;
        final item = state.items[i];
        if (item.status != BatchItemStatus.pending) continue;
        // Хэш именно этого файла — пул уже мог посчитать его давно.
        final hash = await hashes[i];
        if (_cancelled || _disposed) break;
        _setStatus(i, BatchItemStatus.active);
        await _uploadOne(i, item, mediaType, hash);
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
      // Уведомление — последним: сбой плагина не должен оставить пачку
      // в isRunning навсегда. Ошибку гасит сам _clearNotification.
      await _clearNotification();
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
        // Индекс элемента, а не позиция в indices: pending-файлы после
        // повтора идут не с начала пачки (0 — done, 1 — failed→pending).
        // Взяв позицию, пул хэшировал бы не тот файл, а ожидающий
        // настоящего индекса не дождался бы своего хэша никогда —
        // пачка зависала бы в isRunning до перезапуска.
        final i = indices[cursor++];
        final item = state.items[i];
        String? hash;
        try {
          hash = await _single.hasher(
            item.source,
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
  ///
  /// Тип берётся у прошлой пачки, а не у экрана: пачка общая для аудио и
  /// видео, и после возврата на экран другого типа переданный извне тип
  /// ушёл бы на сервер чужим (аудио-файлы записались бы как видео).
  ///
  /// [collectionId] — коллекция, выбранная на экране сейчас, а не та, с
  /// которой стартовал прошлый прогон: после пачки выбор можно сменить,
  /// и повтор обязан уйти в видимую пользователю коллекцию.
  Future<BatchUploadState> retryFailed({required int? collectionId}) async {
    if (state.isRunning) return state;
    final mediaType = _mediaType;
    // Повтор возможен только после прогона — тип у него уже есть.
    if (mediaType == null) return state;
    state = BatchUploadState(
      items: [
        for (final item in state.items)
          if (item.status == BatchItemStatus.failed)
            item.copyWith(status: BatchItemStatus.pending)
          else
            item,
      ],
    );
    return await startAll(mediaType: mediaType, collectionId: collectionId);
  }

  Future<void> _uploadOne(
    int index,
    BatchUploadItem item,
    String mediaType,
    String? knownHash,
  ) async {
    var ok = false;
    String? duplicateTitle;
    try {
      ok = await _single.start(
        source: item.source,
        mediaType: mediaType,
        length: item.fileSize,
        knownHash: knownHash,
        onDuplicateTitle: (title) => duplicateTitle = title,
        // Без pop экрана: пачка продолжается. Списки обновляем теми же
        // провайдерами, что refreshMediaLists, но напрямую: ref нотифаера —
        // Ref, а не WidgetRef, в сигнатуру он не входит.
        onSuccess: (mediaId) async {
          ref
            ..invalidate(mediaListProvider('video'))
            ..invalidate(mediaListProvider('audio'));
          if (mediaId != null) await _addToCollection(mediaId);
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

  /// Кладёт загруженный файл в выбранную коллекцию.
  ///
  /// Сбой добавления не должен валить загрузку: файл уже на сервере, и
  /// `false` из `start` пометил бы его упавшим. Поэтому и Left, и
  /// исключение здесь только считаются и логируются.
  Future<void> _addToCollection(int mediaId) async {
    final collectionId = _collectionId;
    if (collectionId == null) return;
    try {
      final result = await ref
          .read(collectionsRepositoryProvider)
          .addCollectionItem(collectionId, mediaId);
      if (result.isRight()) return;
      AppLogger.error(
        'Failed to add media $mediaId to collection $collectionId',
        result.fold((failure) => failure, (_) => null),
      );
    } catch (e, st) {
      AppLogger.error(
        'Failed to add media $mediaId to collection $collectionId',
        e,
        st,
      );
    }
    // Счётчик, а не снекбар на каждый файл: при пачке в 20 серий
    // двадцать одинаковых сообщений — шум.
    _collectionFailures++;
  }

  /// Показывает уведомление о прогрессе пачки.
  ///
  /// Уведомление — единственный экран прогресса вне приложения: без него
  /// ушедший с экрана загрузки не видит, что загрузка идёт.
  ///
  /// Сбой плагина гасится здесь: уведомления не должны ломать загрузку
  /// (на Linux без демона уведомлений, при отозванном разрешении и т.п.).
  Future<void> _showNotification({
    required int done,
    required int total,
    double? progress,
  }) async {
    final notifications = ref.read(uploadNotificationsProvider);
    if (notifications == null) return;
    try {
      await notifications.showProgress(
        done: done,
        total: total,
        progress: progress,
      );
    } catch (e, st) {
      AppLogger.error('Upload notification failed', e, st);
    }
  }

  /// Обновление уведомления с дросселем: в шторку нельзя писать часто.
  void _updateNotification({
    required int done,
    required int total,
    double? progress,
  }) {
    final now = DateTime.now();
    if (now.difference(_lastNotificationUpdate) <
        const Duration(milliseconds: 800)) {
      return;
    }
    _lastNotificationUpdate = now;
    unawaited(_showNotification(done: done, total: total, progress: progress));
  }

  /// Убирает уведомление: пачка закончилась или отменена.
  Future<void> _clearNotification() async {
    final notifications = ref.read(uploadNotificationsProvider);
    if (notifications == null) return;
    try {
      await notifications.clear();
    } catch (e, st) {
      AppLogger.error('Upload notification clear failed', e, st);
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

/// Провайдер пакетной загрузки.
///
/// НЕ autoDispose: уход с экрана загрузки не должен прерывать пачку.
/// Раньше состояние жило вместе с экраном, и при закрытии экрана
/// контроллер умирал — цикл пачки выходил по «_disposed» и остальные
/// файлы просто отбрасывались (пользователь видел, что загрузка
/// «отменилась»). Теперь состояние живёт вместе с процессом: пачка
/// доезжает до конца, а повторный вход на экран показывает, что
/// грузится и с каким прогрессом.
///
/// Плата: состояние переживает экран, поэтому экран сбрасывает его
/// при входе, если ничего не грузится (см. UploadScreen).
final batchUploadControllerProvider =
    NotifierProvider<BatchUploadController, BatchUploadState>(
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

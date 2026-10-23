import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/media/domain/models/upload_source.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';

/// Фазы загрузки для UI.
enum UploadPhase { hashing, checking, uploading, processing }

/// Состояние загрузки.
class UploadState {
  const new({
    this.isUploading = false,
    this.phase,
    this.sentBytes,
    this.totalBytes,
    this.cancelled = false,
    this.errorMessage,
  });

  /// Сброс в покой после завершения (успех/отмена/дубликат/сбой).
  /// Отдельный конструкт, а не copyWith(phase: null): copyWith не умеет
  /// сбрасывать nullable-поля (?? this.phase). Static, а не factory:
  /// const-фабрика триггерит unnecessary_type_name_in_constructor
  /// при кодстайле `const new(...)`, а значения всё равно runtime.
  // ignore: prefer_constructors_over_static_methods
  static UploadState idle({String? errorMessage, bool cancelled = false}) {
    return UploadState(errorMessage: errorMessage, cancelled: cancelled);
  }

  final bool isUploading;
  final UploadPhase? phase;
  final int? sentBytes;
  final int? totalBytes;
  final bool cancelled;

  /// Текст ошибки для фидбека (null — успех, отмена или дубликат).
  ///
  /// Инвариант: любой возврат `false` из [UploadController.start], кроме
  /// отмены и живого дубликата, выставляет errorMessage. Дубликат из
  /// корзины — тоже errorMessage (с намёком на восстановление), а не
  /// молчаливый null. Экран поэтому показывает fileAlreadyExists только
  /// когда ошибки нет — реальный сбой так не замаскируется под «дубликат».
  final String? errorMessage;

  double? get progress =>
      (totalBytes != null && totalBytes! > 0)
          ? ((sentBytes ?? 0) / totalBytes!).clamp(0.0, 1.0)
          : null;

  UploadState copyWith({
    bool? isUploading,
    UploadPhase? phase,
    int? sentBytes,
    int? totalBytes,
    bool? cancelled,
    String? errorMessage,
  }) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      phase: phase ?? this.phase,
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      cancelled: cancelled ?? this.cancelled,
      errorMessage: errorMessage,
    );
  }
}

/// Хэширует файл. Возвращает null, если хэширование отменено.
/// Второй параметр — проверка отмены: хэш 2 ГБ длится секунды, и флаг
/// отмены должен срабатывать внутри, а не после.
typedef FileHasher = Future<String?> Function(
  UploadSource source,
  bool Function() isCancelled,
);

/// Колбэк успешной загрузки: инвалидация списков, снэкбар, закрытие экрана.
/// Передаётся в [UploadController.start] — экрану нужны свежие ref/context,
/// хранить замыкание в поле контроллера нельзя (stale-контекст).
///
/// [mediaId] — id созданного медиа: экран загрузки кладёт файл в
/// выбранную коллекцию, и для этого нужен id, а не только факт успеха.
/// null — сервер не отдал медиа в статусе джоба (защитный случай).
typedef UploadSuccessCallback = Future<void> Function(int? mediaId);

/// Хэшер по умолчанию: читает файл чанками в текущем изоляте.
/// Чанками, а не Isolate.run целиком: между чанками проверяем отмену
/// и отдаём управление event loop — UI не висит даже на 2 ГБ, а отмена
/// во время hashing срабатывает сразу, а не после всего файла.
Future<String?> _defaultHasher(
  UploadSource source,
  bool Function() isCancelled,
) async {
  final collector = _DigestCollector();
  final sink = sha256.startChunkedConversion(collector);
  try {
    await for (final chunk in source.openRead()) {
      if (isCancelled()) return null;
      sink.add(chunk);
    }
  } finally {
    sink.close();
  }
  return collector.digest?.toString();
}

/// Приёмник hex-digest для чанкового хэширования.
class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// Оркестратор загрузки: hash → проверка дубликата → upload → опрос статуса
/// → отмена джоба. Вынесен из `_UploadScreenState`: ~150 строк логики
/// в виджете были непокрыты (file_picker/Isolate в виджет-тестах не поднять).
class UploadController extends Notifier<UploadState> {
  new({
    this.maxUploadSizeBytes = 2 * 1024 * 1024 * 1024,
    this.statusPollInterval = const Duration(milliseconds: 1500),
    this.maxStatusPollFailures = 3,
    this.progressThrottle = const Duration(milliseconds: 150),
  });

  /// Репозиторий — из контейнера, а не поздним связыванием: забытый bind
  /// давал бы криптичный краш на `!`, а stale-инстанс после смены сервера
  /// молча ходил бы не туда.
  MediaRepository get _repository => ref.read(mediaRepositoryProvider);

  FileHasher? _rawHasher;
  FileHasher get _hasher => _rawHasher ?? _defaultHasher;

  /// Лимит сервера по умолчанию (configs/config.yaml: max_upload_size).
  /// Экран читает его же для проверки размера вместо своего хардкода,
  /// чтобы копии не разъехались при настройке.
  final int maxUploadSizeBytes;

  /// Интервал опроса статуса асинхронной upload-джоба.
  final Duration statusPollInterval;

  /// Сколько подряд неудачных опросов статуса допустимо, прежде чем
  /// показать ошибку (сеть может моргнуть).
  final int maxStatusPollFailures;

  /// Троттлинг прогресса: setState на каждый ~64КБ chunk давал бы
  /// десятки тысяч rebuild'ов.
  final Duration progressThrottle;

  @override
  UploadState build() {
    ref.onDispose(() => _disposed = true);
    return const UploadState();
  }

  bool _cancelled = false;
  bool _disposed = false;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Запускает загрузку [source]. Возвращает true только при полном
  /// успехе (включая onSuccess). См. инвариант [UploadState.errorMessage].
  /// [length] — размер файла в байтах: multipart объявляет Content-Length,
  /// а нулевой размер означает пустой файл.
  /// [knownHash] — заранее посчитанный хэш (пачка считает их конвейером
  /// во время заливки соседних файлов): пропускаем повторный прогон.
  /// [onDuplicateTitle] — existing title дубликата для подписи в пачке.
  Future<bool> start({
    required UploadSource source,
    required String mediaType,
    required int length,
    required UploadSuccessCallback onSuccess,
    String? knownHash,
    void Function(String? existingTitle)? onDuplicateTitle,
  }) async {
    // Backstop-проверки с сырым английским текстом (как Failure.message):
    // errorMessage обязателен — иначе нарушился бы инвариант
    // UploadState.errorMessage и экран показал бы «дубликат».
    if (length == 0) {
      state = state.copyWith(errorMessage: 'Cannot upload an empty file');
      return false;
    }
    if (length > maxUploadSizeBytes) {
      state = state.copyWith(errorMessage: 'File exceeds the upload size limit');
      return false;
    }
    if (source.name.isEmpty) {
      state = state.copyWith(errorMessage: 'Missing file name');
      return false;
    }

    _cancelled = false;
    _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    state = const UploadState(
      isUploading: true,
      phase: UploadPhase.hashing,
    );

    try {
      // knownHash из пачки считается тем же хэшером: null только при отмене.
      final hash = knownHash ?? await _hasher(source, () => _cancelled);
      // null от хэшера — тоже отмена: единственный легитимный
      // производитель null — сработавшая проверка isCancelled внутри.
      if (hash == null) {
        _cancelled = true;
        return false;
      }
      if (_cancelled || _disposed) return false;

      state = state.copyWith(phase: UploadPhase.checking);

      final checkResult = await _repository.checkHash(hash);
      final check = checkResult.fold((failure) {
        // Ошибка сети не должна молча превращаться в «дубликатов нет».
        // Failure не extends Exception — только через ignore.
        // ignore: only_throw_errors
        throw failure;
      }, (data) => data);
      if (_cancelled || _disposed) return false;

      if (check.exists) {
        // Содержимое из корзины — не молчаливый «дубликат», а текст
        // с путём к восстановлению: иначе перезалив упирался бы
        // в оранжевый тупик (бэкенд trashed-флаг отдаёт именно для этого).
        if (check.trashed) {
          state = state.copyWith(
            errorMessage: 'File is in trash — restore it from trash',
          );
        } else {
          onDuplicateTitle?.call(check.title);
        }
        return false;
      }

      state = state.copyWith(phase: UploadPhase.uploading);

      final result = await _repository.uploadFile(
        source: source,
        length: length,
        mediaType: mediaType,
        onProgress: _onProgress,
        isCancelled: () => _cancelled,
      );

      if (_cancelled || _disposed) return false;

      // При обрыве POST jobId неизвестен (UploadCancelledFailure его не
      // содержит) — отменять нечего, просто пробрасываем. Штатный путь
      // «отмена между POST и первым опросом» — ветка ниже.
      final jobId = result.fold((failure) {
        // Failure не extends Exception — только через ignore.
        // ignore: only_throw_errors
        throw failure;
      }, (r) => r.jobId);
      if (_cancelled || _disposed) {
        // Отмена ровно между POST и первым опросом: джоб уже создан на
        // сервере — отменяем его явно. При dispose (уход с экрана) джоб
        // не трогаем: экран при размонтировании сам решит.
        if (_cancelled && !_disposed) await _cancelJob(jobId);
        return false;
      }

      state = state.copyWith(phase: UploadPhase.processing);
      final poll = await _pollUploadStatus(jobId);
      if (!poll.done) {
        if (poll.error != null) state = state.copyWith(errorMessage: poll.error);
        return false;
      }

      await onSuccess(poll.mediaId);
      return true;
    } on Failure catch (e) {
      AppLogger.error('Upload failed', e);
      state = state.copyWith(errorMessage: e.message);
      return false;
    } catch (e, st) {
      AppLogger.error('Upload failed', e, st);
      state = state.copyWith(errorMessage: e.toString());
      return false;
    } finally {
      // Сбрасываем ошибку при успехе, оставляем при сбое — экран читает
      // errorMessage для фидбека. cancelled сохраняем: экран отличает
      // отмену от сетевой ошибки по этому флагу.
      // После dispose состояние не трогаем — провайдер мёртв.
      if (!_disposed) {
        final hadError = state.errorMessage != null;
        // sent/total/phase тоже сбрасываем: прогресс нужен только во
        // время загрузки, а stale-значения после успеха ничему не служат.
        state = UploadState.idle(
          errorMessage: hadError ? state.errorMessage : null,
          cancelled: _cancelled,
        );
      }
    }
  }

  /// Подмена хэшера в тестах. Репозиторий инжектить не надо — он из ref.
  FileHasher get hasher => _hasher;
  set hasher(FileHasher hasher) => _rawHasher = hasher;

  /// Отменяет загрузку. Хэширование и загрузка прерываются на ближайшей
  /// проверке `_cancelled`; опрос статуса — немедленно.
  void cancel() {
    _cancelled = true;
  }

  void _onProgress(int sent, int? total) {
    if (_disposed) return;
    final now = DateTime.now();
    final isFinal = sent >= (total ?? sent);
    if (!isFinal && now.difference(_lastProgressUpdate) < progressThrottle) {
      return;
    }
    _lastProgressUpdate = now;
    state = state.copyWith(sentBytes: sent, totalBytes: total);
  }

  /// Опрашивает статус джоба каждые ~1.5 с до done/error/отмены.
  /// Ошибка возвращается текстом (а не только флагом): иначе экран не
  /// отличил бы сбой обработки от дубликата и показал бы
  /// «файл уже существует».
  Future<({bool done, String? error, int? mediaId})> _pollUploadStatus(
    int jobId,
  ) async {
    var consecutiveFailures = 0;
    String? lastError;
    int? mediaId;

    while (!_cancelled && !_disposed) {
      await Future<void>.delayed(statusPollInterval);
      if (_cancelled || _disposed) break;

      final result = await _repository.getUploadStatus(jobId);
      if (_cancelled || _disposed) break;

      final shouldStop = result.fold(
        (failure) {
          if (failure is UploadCancelledFailure) return true;
          consecutiveFailures++;
          lastError = failure.message;
          return consecutiveFailures >= maxStatusPollFailures;
        },
        (status) {
          consecutiveFailures = 0;
          if (status.isError) {
            lastError = status.error;
            return true;
          }
          // Готовый джоб отдаёт созданное медиа — его id нужен
          // вызывающему (положить файл в коллекцию).
          mediaId = status.media?.id;
          return status.isDone;
        },
      );
      if (shouldStop) {
        final done = result.fold((_) => false, (s) => s.isDone);
        if (done) return (done: true, error: null, mediaId: mediaId);
        // status.error может быть null — тогда fallback вместо молчания:
        // иначе экран покажет «дубликат».
        return (
          done: false,
          error: lastError ?? 'Upload processing failed',
          mediaId: null,
        );
      }
    }

    // Пользователь отменил во время обработки — отменяем джоб на
    // сервере, чтобы файл не сохранился в библиотеке.
    if (_cancelled && !_disposed) {
      await _cancelJob(jobId);
    }
    return (done: false, error: null, mediaId: null);
  }

  Future<void> _cancelJob(int jobId) async {
    final result = await _repository.cancelUpload(jobId);
    result.fold(
      (failure) =>
          AppLogger.error('Failed to cancel upload job $jobId', failure),
      (_) {},
    );
  }
}

/// Провайдер контроллера загрузки. autoDispose: прогресс/ошибка —
/// состояние экрана, после закрытия чистим. Незавершённый поллинг
/// прерывается флагом _disposed (см. _pollUploadStatus и _onProgress).
final uploadControllerProvider =
    NotifierProvider.autoDispose<UploadController, UploadState>(
      UploadController.new,
    );

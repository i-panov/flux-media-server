import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/video/presentation/providers/extracted_audio_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Состояние извлечения аудио из видео.
class ExtractState {
  const new({
    this.isExtracting = false,
    this.jobId,
    this.cancelled = false,
    this.errorMessage,
  });

  final bool isExtracting;

  /// Активный джоб (для отмены и отладки).
  final int? jobId;
  final bool cancelled;

  /// Текст ошибки для фидбека (null — успех, отмена или «ещё не started»).
  ///
  /// Тот же инвариант, что у UploadState.errorMessage: любой возврат
  /// null из [ExtractController.start], кроме отмены, выставляет ошибку.
  ///
  /// Backstop про язык: содержимое errorMessage — всегда сырой английский
  /// (сообщения сервера, Failure.message, три фолбэка ниже). Локализуется
  /// только обёртка во флоу (extractFailed), а не детали: серверные тексты
  /// всё равно приходят английскими, и выборочный перевод трёх наших
  /// строк дал бы смешанный язык в одном снекбаре вместо честного сырого.
  final String? errorMessage;

  /// Сброс в покой после завершения.
  /// Static, а не factory: const-фабрика триггерит
  /// unnecessary_type_name_in_constructor при кодстайле `const new(...)`,
  /// а значения всё равно runtime.
  // ignore: prefer_constructors_over_static_methods
  static ExtractState idle({String? errorMessage, bool cancelled = false}) {
    return ExtractState(errorMessage: errorMessage, cancelled: cancelled);
  }

  ExtractState copyWith({
    bool? isExtracting,
    int? jobId,
    bool? cancelled,
    // Сентинел вместо ?? this: частичное копирование (например, jobId)
    // не должно затирать уже выставленную ошибку.
    Object? errorMessage = _keepError,
  }) {
    return ExtractState(
      isExtracting: isExtracting ?? this.isExtracting,
      jobId: jobId ?? this.jobId,
      cancelled: cancelled ?? this.cancelled,
      errorMessage: errorMessage == _keepError
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const _keepError = Object();
}

/// Оркестратор извлечения аудио: POST → (готовый трек | опрос статуса).
/// Упрощённый родственник UploadController: без файлов, хэшей и прогресса.
///
/// Пост-успешную инвалидацию (списки + связка) делает сам контроллер на
/// своём ref, а не колбэк экрана: экран может размонтироваться посреди
/// опроса, и замыкание с мёртвым WidgetRef уронило бы обновление —
/// вернувшийся юзер видел бы stale-кнопку до ручного pull-to-refresh.
/// Зависимость media→video (extractedAudioProvider) — осознанная и
/// однонаправленная: обратных импортов нет, цикла нет.
class ExtractController extends Notifier<ExtractState> {
  new({
    this.statusPollInterval = const Duration(milliseconds: 1500),
    this.maxStatusPollFailures = 3,
  });

  /// Репозиторий — из контейнера (см. UploadController: поздний bind
  /// давал криптичный краш и stale-инстансы).
  MediaRepository get _repository => ref.read(mediaRepositoryProvider);

  /// Интервал опроса статуса джоба.
  final Duration statusPollInterval;

  /// Сколько подряд неудачных опросов допустимо (сеть может моргнуть).
  final int maxStatusPollFailures;

  @override
  ExtractState build() {
    ref.onDispose(() => _disposed = true);
    return const ExtractState();
  }

  bool _cancelled = false;
  bool _disposed = false;

  /// In-flight дедупликация запусков: двойной тап — один джоб, оба
  /// получат один и тот же future (паттерн download() кеш-сервиса).
  Future<Media?>? _inFlight;

  /// Запускает извлечение. Возвращает трек или null (сбой/отмена —
  /// см. инвариант [ExtractState.errorMessage]). Снекбары — дело экрана
  /// по mounted; данные (списки + связка) обновляет сам контроллер.
  Future<Media?> start({required int mediaId}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _startInner(mediaId: mediaId);
    _inFlight = future;
    unawaited(
      future.then((_) => _inFlight = null, onError: (_) => _inFlight = null),
    );
    return future;
  }

  Future<Media?> _startInner({required int mediaId}) async {
    _cancelled = false;
    state = const ExtractState(isExtracting: true);

    try {
      final submitted = await _repository.extractAudio(
        mediaId,
        isCancelled: () => _cancelled,
      );
      final target = submitted.fold((failure) {
        // Failure не extends Exception — только через ignore.
        // ignore: only_throw_errors
        throw failure;
      }, (r) => r);
      if (_cancelled || _disposed) return null;

      // Трек уже извлечён: опрашивать нечего.
      if (target.media != null) {
        _refreshAfterSuccess(mediaId);
        return target.media;
      }
      final jobId = target.jobId;
      if (jobId == null) {
        state = state.copyWith(errorMessage: 'Unexpected server response');
        return null;
      }
      state = state.copyWith(jobId: jobId);

      final poll = await _pollExtractStatus(jobId);
      if (!poll.done) {
        if (poll.error != null) {
          state = state.copyWith(errorMessage: poll.error);
        }
        return null;
      }
      final media = poll.media;
      if (media == null) {
        state = state.copyWith(errorMessage: 'Extracted track not found');
        return null;
      }

      _refreshAfterSuccess(mediaId);
      return media;
    } on Failure catch (e) {
      AppLogger.error('Audio extraction failed', e);
      if (!_disposed) state = state.copyWith(errorMessage: e.message);
      return null;
    } catch (e, st) {
      AppLogger.error('Audio extraction failed', e, st);
      if (!_disposed) state = state.copyWith(errorMessage: e.toString());
      return null;
    } finally {
      if (!_disposed) {
        final hadError = state.errorMessage != null;
        state = ExtractState.idle(
          errorMessage: hadError ? state.errorMessage : null,
          cancelled: _cancelled,
        );
      }
    }
  }

  /// Отменяет извлечение: опрос прерывается, джоб отменяется на сервере.
  void cancel() {
    _cancelled = true;
  }

  /// Пост-успешное обновление данных на живом ref провайдера (а не
  /// экрана): переживает уход со экрана, поэтому вернувшийся юзер
  /// видит свежую связку и списки без ручного обновления.
  /// Дублирует refreshMediaLists(): та принимает WidgetRef, а ref
  /// контроллера в этой версии Riverpod — другой тип.
  void _refreshAfterSuccess(int mediaId) {
    ref
      ..invalidate(mediaListProvider('video'))
      ..invalidate(mediaListProvider('audio'))
      ..invalidate(extractedAudioProvider(mediaId));
  }

  Future<({bool done, Media? media, String? error})> _pollExtractStatus(
    int jobId,
  ) async {
    var consecutiveFailures = 0;
    String? lastError;

    while (!_cancelled && !_disposed) {
      await Future<void>.delayed(statusPollInterval);
      if (_cancelled || _disposed) break;

      final result = await _repository.getExtractStatus(
        jobId,
        isCancelled: () => _cancelled,
      );
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
          return status.isDone;
        },
      );
      if (shouldStop) {
        final done = result.fold((_) => false, (s) => s.isDone);
        if (done) {
          final media = result.fold((_) => null, (s) => s.media);
          return (done: true, media: media, error: null);
        }
        return (
          done: false,
          media: null,
          error: lastError ?? 'Audio extraction failed',
        );
      }
    }

    if (_cancelled && !_disposed) {
      await _cancelJob(jobId);
    }
    return (done: false, media: null, error: null);
  }

  Future<void> _cancelJob(int jobId) async {
    // Без isCancelled осознанно: флаг уже взведён, и запрос отмены
    // абортил бы сам себя (как в UploadController._cancelJob).
    final result = await _repository.cancelExtract(jobId);
    result.fold(
      (failure) =>
          AppLogger.error('Failed to cancel extract job $jobId', failure),
      (_) {},
    );
  }
}

/// Провайдер контроллера извлечения. НЕ autoDispose (как upload):
/// уход с экрана не убивает опрос — трек появляется молча, отмена —
/// только явной кнопкой. Состояние переживает навигацию осознанно.
final extractControllerProvider =
    NotifierProvider<ExtractController, ExtractState>(
      ExtractController.new,
    );

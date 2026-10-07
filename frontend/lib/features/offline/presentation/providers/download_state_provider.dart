import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Состояние загрузки одного медиа.
///
/// Иерархия классов, а не freezed/sealed с фабриками: у состояний разные
/// наборы полей, и сравнение нужно только прогрессу (остальные сравниваются
/// по типу).
@immutable
sealed class DownloadState {
  const new();
}

class DownloadIdle extends DownloadState {
  const new();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DownloadIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
class DownloadDownloading extends DownloadState {
  const new({this.progress = 0.0});

  final double progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadDownloading && other.progress == progress;

  @override
  int get hashCode => progress.hashCode;
}

class DownloadDownloaded extends DownloadState {
  const new();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DownloadDownloaded;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
class DownloadError extends DownloadState {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Состояние загрузок всех медиа: один экземпляр на приложение.
///
/// Раньше был `Notifier` на каждый `mediaId` — копия жила до конца сеанса,
/// а при `autoDispose` прогресс активной загрузки терялся (экземпляр
/// умирал между `ref.read` вызовами). Здесь состояние переживает навигацию
/// и при этом не растёт: в карте только те id, у которых состояние
/// отличается от idle; когда записей становится больше [_keepAtMost],
/// самые старые завершённые выкидываются. Выкинутый id при следующем
/// показе перепроверяется через `checkStatus`, поэтому скачанный файл
/// никогда не показывается как «не скачано» надолго.
class DownloadsStateNotifier extends Notifier<Map<int, DownloadState>> {
  /// Сколько завершённых записей держим в памяти до уборки.
  static const _keepAtMost = 128;

  /// Время последнего обновления прогресса по id — троттлинг rebuild-ов.
  final Map<int, DateTime> _lastProgressUpdate = {};

  /// id, для которых проверка наличия файла в кеше уже выполнялась.
  ///
  /// Отдельно от [_touched]: проверка idle-записей в `_set` выходит
  /// раньше и карту не трогает, поэтому сотни просмотренных, но не
  /// скачанных карточек сюда попадали бы без ограничений и без чистки.
  /// LinkedHashSet хранит порядок вставки — выкидываем самые старые;
  /// выкинутый id при следующем показе просто перепроверяется.
  /// Лимит тот же, что у [_keepAtMost]: обе карты про одни и те же id.
  final Set<int> _checked = {};

  /// Когда состояние менялось последний раз — по этому сортируем уборку.
  final Map<int, DateTime> _touched = {};

  @override
  Map<int, DownloadState> build() => const {};

  /// Состояние [mediaId]; idle, если записи нет.
  DownloadState stateOf(int mediaId) => state[mediaId] ?? const DownloadIdle();

  /// Отмечает [mediaId] как проверенный и сообщает, нужно ли проверять
  /// наличие файла. Первичная проверка делается один раз за сеанс: без
  /// неё карточка никогда не показала бы «скачано» для файла,
  /// скачанного в прошлом запуске.
  bool markChecked(int mediaId) {
    final isNew = _checked.add(mediaId);
    while (_checked.length > _keepAtMost) {
      _checked.remove(_checked.first);
    }
    return isNew;
  }

  OfflineCacheService get _cacheService =>
      ref.read(offlineCacheServiceProvider);

  void _set(int mediaId, DownloadState next) {
    final current = state[mediaId];
    if (current == next) return;
    if (next is DownloadIdle) {
      if (current == null) return;
      _touched.remove(mediaId);
      state = {...state}..remove(mediaId);
      return;
    }
    _touched[mediaId] = DateTime.now();
    state = {...state, mediaId: next};
    _prune();
  }

  /// Убирает самые старые завершённые записи, когда карта разрослась.
  ///
  /// Уборка по событию записи, а не по таймеру: таймер жил бы до получаса
  /// и держал isolate. Активные загрузки не трогаем.
  void _prune() {
    final excess = _touched.length - _keepAtMost;
    if (excess <= 0) return;
    final candidates =
        _touched.entries
            .where((e) => state[e.key] is! DownloadDownloading)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    final doomed = candidates.take(excess).map((e) => e.key).toSet();
    if (doomed.isEmpty) return;
    _touched.removeWhere((k, _) => doomed.contains(k));
    _lastProgressUpdate.removeWhere((k, _) => doomed.contains(k));
    // Выкинутые id снова считаются непроверенными: при следующем показе
    // checkStatus восстановит их актуальное состояние из кеша.
    _checked.removeAll(doomed);
    state = {...state}..removeWhere((k, _) => doomed.contains(k));
  }

  /// Checks if the media item is already downloaded.
  Future<void> checkStatus(int mediaId) async {
    final cached = await _cacheService.isCached(mediaId);
    // Применяем результат только из idle: гонка с download (результат
    // isCached, полученный до завершения загрузки) не откатывает
    // состояние downloaded/error/downloading.
    final current = state[mediaId];
    if (current != null && current is! DownloadIdle) return;
    _set(mediaId, cached ? const DownloadDownloaded() : const DownloadIdle());
  }

  /// Starts downloading the media item with progress tracking.
  ///
  /// Повторный старт того же id, пока он грузится, — тихий игнор, а не
  /// ошибка: иначе двойной тап давал мигание error → downloaded.
  Future<void> download(Media media) async {
    if (state[media.id] is DownloadDownloading) return;
    _set(media.id, const DownloadDownloading());
    try {
      await _cacheService.download(
        media,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            final progress = received / total;
            // Троттлинг ~100 мс: иначе каждый чанк делает rebuild.
            final now = DateTime.now();
            final last = _lastProgressUpdate[media.id];
            if (last == null ||
                now.difference(last) >= const Duration(milliseconds: 100)) {
              _lastProgressUpdate[media.id] = now;
              _set(media.id, DownloadDownloading(progress: progress));
            }
          }
        },
      );
      _set(media.id, const DownloadDownloaded());
      ref.read(downloadsInvalidatorProvider.notifier).state++;
    } on DownloadCancelledException {
      _set(media.id, const DownloadIdle());
    } on FileSystemException catch (e) {
      // Маппим нехватку места на диске в человекочитаемое сообщение.
      final noSpace =
          e.osError?.errorCode == 28 ||
          e.message.toLowerCase().contains('no space');
      _set(
        media.id,
        DownloadError(
          noSpace
              ? 'Not enough storage space. Free up space and try again.'
              : e.message,
        ),
      );
    } catch (e, st) {
      AppLogger.error('Download failed', e, st);
      _set(media.id, DownloadError(e.toString()));
    } finally {
      _lastProgressUpdate.remove(media.id);
    }
  }

  /// Отменяет активную загрузку и ждёт её фактического завершения.
  ///
  /// Фидбек «отменено» показывается только после реальной чистки .part,
  /// а рестарт сразу после отмены уже не упирается в «already in
  /// progress»: к моменту возврата флаг активности снят.
  Future<void> cancel(int mediaId) async {
    await _cacheService.cancelAndJoin(mediaId);
    _lastProgressUpdate.remove(mediaId);
    _set(mediaId, const DownloadIdle());
  }

  /// Removes the downloaded file.
  Future<void> remove(int mediaId) async {
    await _cacheService.remove(mediaId);
    _lastProgressUpdate.remove(mediaId);
    _set(mediaId, const DownloadIdle());
    ref.read(downloadsInvalidatorProvider.notifier).state++;
  }
}

/// Состояния загрузок по всем медиа: один keepAlive-экземпляр.
final downloadsStateProvider =
    NotifierProvider<DownloadsStateNotifier, Map<int, DownloadState>>(
      DownloadsStateNotifier.new,
    );

/// Состояние загрузки конкретного медиа.
///
/// Тонкая обёртка над [downloadsStateProvider]: `select` пересобирает виджет
/// только при смене состояния ЭТОГО id, а не любой загрузки. autoDispose
/// здесь безопасен: само состояние живёт в keepAlive-карте, поэтому уход
/// экрана не обрывает прогресс активной загрузки.
final downloadStateProvider = Provider.autoDispose.family<DownloadState, int>((
  ref,
  mediaId,
) {
  final notifier = ref.read(downloadsStateProvider.notifier);
  if (notifier.markChecked(mediaId)) unawaited(notifier.checkStatus(mediaId));
  return ref.watch(downloadsStateProvider.select((s) => s[mediaId])) ??
      const DownloadIdle();
});

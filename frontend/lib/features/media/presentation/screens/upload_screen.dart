import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/select_collection_dialog.dart';
import 'package:flux_media_server/features/media/domain/models/upload_source.dart';
import 'package:flux_media_server/features/media/presentation/providers/batch_upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class UploadScreen extends ConsumerStatefulWidget {
  const new({required this.mediaType, super.key});

  final String mediaType;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  @override
  void initState() {
    super.initState();
    // Состояние пачки переживает экран (иначе уход прерывал бы загрузку),
    // поэтому на входе сбрасываем его, если ничего не грузится: экран
    // открывается с чистым листом. Пока идёт загрузка — сброс не
    // срабатывает, и пользователь видит текущую пачку.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(batchUploadControllerProvider.notifier).clear();
    });
  }

  /// Коллекция, в которую попадут все файлы пачки (null — без неё).
  ///
  /// Выбор живёт в состоянии экрана, а сама раскладка по коллекции — в
  /// пакетном контроллере: пачка переживает экран, поэтому id уходит в
  /// [BatchUploadController.startAll]. Дублировать его в состоянии
  /// контроллера незачем — там только счётчик ошибок для сводки.
  int? _collectionId;
  String? _collectionName;

  /// Тип коллекции, выбранной для пачки. Сервер тип пары «медиа —
  /// коллекция» не сверяет, поэтому набор файлов и коллекция обязаны
  /// совпадать по типу: иначе видео уедет в аудиоколлекцию.
  MediaType? _collectionType;

  /// Тип файлов этого экрана.
  MediaType get _screenType =>
      widget.mediaType == 'audio' ? MediaType.audio : MediaType.video;

  /// Тип файлов, к которым относится выбор коллекции и запуск: у
  /// существующей пачки — её тип (экран мог быть открыт с другой вкладки),
  /// иначе — тип экрана.
  MediaType get _filesType {
    final batchType = ref
        .read(batchUploadControllerProvider.notifier)
        .mediaType;
    return switch (batchType) {
      'audio' => MediaType.audio,
      'video' => MediaType.video,
      _ => _screenType,
    };
  }

  String _formatSize(int bytes) {
    // 0 — размер ещё не догрузился: не показываем ложные «0.0 KB».
    if (bytes == 0) return '…';
    if (bytes > 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  /// Мультивыбор: pickFiles на Android уже отдаёт несколько файлов.
  /// Пути может не быть (облачные провайдеры) — такие пропускаем:
  /// грузить нечего, а молча ронять пачку нельзя.
  ///
  /// Файлы копируются плагином в кэш приложения — это его единственный
  /// способ отдать содержимое: системный SAF-пикер отдаёт content://-ссылку,
  /// которую без нативного кода читать нечем. Плагин file_selector
  /// отдаёт такие ссылки, но вдобавок читает файл целиком в память
  /// (`new byte[size]`), а на видео в гигабайты это OutOfMemory.
  ///
  /// Пока копирование не убрано, список появляется после него — отсюда
  /// пауза на пустом экране. Свой пикер (content:// напрямую, без копии)
  /// — следующий шаг.
  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.mediaType == 'audio'
          ? ['mp3', 'flac', 'ogg', 'm4a', 'aac', 'wav', 'opus', 'wma']
          : ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v'],
    );
    // Метки этапов: если между «пикер вернулся» и списком есть дыра,
    // видно в logcat, где именно (плагин/размеры/построение).
    AppLogger.info('Batch picker returned: ${result.length} file(s)');
    if (result.isEmpty) return;

    final sources = <UploadSource>[];
    for (final file in result) {
      final path = file.path;
      if (path == null) continue;
      sources.add(
        UploadSource(
          path: path,
          name: file.name,
          openRead: () => File(path).openRead(),
        ),
      );
    }
    if (sources.isEmpty) return;
    // Файлы нового набора — типа этого экрана. Коллекция, выбранная
    // раньше, могла быть другого типа (picker фильтрует по типу пачки,
    // а она могла прийти с другой вкладки) — такой выбор к новому набору
    // не относится. Сброс до показа списка: строка коллекции не должна
    // показывать то, куда файлы не попадут.
    final collectionType = _collectionType;
    if (mounted && collectionType != null && collectionType != _screenType) {
      _clearCollection();
    }
    // Список показываем СРАЗУ, с нулевыми размерами: экран не должен
    // ждать замеров. Размеры догружаются фоном и обновляют строки.
    ref.read(batchUploadControllerProvider.notifier).setFiles(
      [
        for (final source in sources)
          BatchUploadItem(source: source, fileSize: 0),
      ],
      // 0 в размере ниже — «ещё не измерено»: старт заблокирован,
      // пока не придёт updateSizes (иначе быстрый тап = «empty file»).
      sizesPending: true,
    );
    AppLogger.info('Batch list shown: ${sources.length} file(s)');

    final sizes = await Future.wait([
      for (final source in sources)
        // Размер читаем асинхронно: lengthSync() блокирует UI-изолят.
        File(source.path).length().then((s) => MapEntry(source.path, s)),
    ]);
    if (!mounted) return;
    ref.read(batchUploadControllerProvider.notifier).updateSizes({
      for (final e in sizes) e.key: e.value,
    });
    AppLogger.info('Batch sizes resolved: ${sizes.length}');
  }

  Future<void> _startAll() async {
    await ref
        .read(batchUploadControllerProvider.notifier)
        .startAll(mediaType: widget.mediaType, collectionId: _collectionId);
    if (!mounted) return;
    _showSummary();
  }

  Future<void> _retryFailed() async {
    // Тип пачки контроллер помнит сам: экран может быть открыт с другой
    // вкладки (например, видео при идущей аудио-пачке), и присланный
    // отсюда тип ушёл бы на сервер чужим. Коллекция же — выбор этого
    // экрана: после пачки его можно сменить, и повтор идёт в видимую.
    await ref
        .read(batchUploadControllerProvider.notifier)
        .retryFailed(collectionId: _collectionId);
    if (!mounted) return;
    _showSummary();
  }

  /// Выбор коллекции для всей пачки: и загрузка, и создание новой —
  /// прямо отсюда (иначе выбирать было бы нечего).
  Future<void> _pickCollection() async {
    final collection = await showSelectCollectionDialog(
      context,
      ref,
      type: _filesType,
    );
    if (collection == null || !mounted) return;
    setState(() {
      _collectionId = collection.id;
      _collectionName = collection.name;
      _collectionType = collection.type;
    });
  }

  /// Забывает выбранную коллекцию: набор файлов сменился, и прежний
  /// выбор к нему уже не относится.
  void _clearCollection() {
    setState(() {
      _collectionId = null;
      _collectionName = null;
      _collectionType = null;
    });
  }

  /// Итог прогона одной сводкой: зелёная только при полном успехе,
  /// дубликаты — не ошибка, ошибки уже видны построчно.
  void _showSummary() {
    final summary = ref.read(batchUploadControllerProvider);
    final total = summary.items.length;
    if (total == 0) return;
    final collectionFailures = ref
        .read(batchUploadControllerProvider.notifier)
        .collectionFailures;
    // Зелёный только при полном успехе, иначе нейтральный итог:
    // дубликаты — не ошибка, ошибки уже видны построчно.
    final allDone =
        summary.failedCount == 0 &&
        summary.duplicateCount == 0 &&
        collectionFailures == 0;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.uploadBatchSummary(
                  summary.doneCount,
                  total,
                  summary.duplicateCount,
                  summary.failedCount,
                ),
              ),
              if (collectionFailures > 0)
                Text(l.failedToAddToCollection(collectionFailures)),
            ],
          ),
          backgroundColor: allDone ? Colors.green : null,
        ),
      );
  }

  void _cancelAll() {
    ref.read(batchUploadControllerProvider.notifier).cancelAll();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final batch = ref.watch(batchUploadControllerProvider);
    final single = ref.watch(uploadControllerProvider);

    final activeIndex = batch.items.indexWhere(
      (i) => i.status == BatchItemStatus.active,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.uploadMedia),
        actions: [
          if (batch.isRunning)
            IconButton(
              onPressed: _cancelAll,
              icon: const Icon(Icons.close),
              tooltip: l.cancel,
            )
          else ...[
            if (batch.failedCount > 0)
              IconButton(
                onPressed: _retryFailed,
                icon: const Icon(Icons.refresh),
                tooltip: l.retry,
              ),
            // Нет pending-файлов — грузить нечего: после завершённой
            // пачки остаётся только «Повторить» (упавшие) или ничего.
            // Кнопка, которая молча ничего не делает, ещё и путала бы:
            // нажатие по чужой пачке переписывало её тип и коллекцию.
            if (batch.pendingCount > 0)
              TextButton.icon(
                // Пока размеры не догрузились — старт запрещён: 0 в
                // fileSize означает «не измерено», а контроллер трактует
                // 0 как пустой файл и валит его backstop-ошибкой.
                onPressed: batch.sizesPending ? null : _startAll,
                icon: const Icon(Icons.cloud_upload),
                label: Text(l.upload),
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: batch.isRunning ? null : _pickFiles,
                icon: Icon(
                  batch.items.isNotEmpty
                      ? Icons.check_circle
                      : Icons.attach_file,
                ),
                label: Text(
                  batch.items.isEmpty
                      ? l.selectFiles
                      : l.selectedFiles(batch.items.length),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Куда сложить загруженное: одна коллекция на всю пачку.
          // Без этого сезон из 20 серий после загрузки лежал в общем
          // списке, и раскладывать его по коллекциям приходилось вручную,
          // по одному файлу.
          if (batch.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CollectionPicker(
                name: _collectionName,
                enabled: !batch.isRunning,
                onTap: _pickCollection,
                onClear: _clearCollection,
              ),
            ),
          const SizedBox(height: 8),
          // Фаза хэширования видна честным прогрессом: иначе пачка
          // на 20 серий молчит, пока пул считает хэши.
          if (batch.isHashing) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: batch.hashingTotal > 0
                        ? batch.hashingDone / batch.hashingTotal
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l.hashingFile} ${batch.hashingDone}/${batch.hashingTotal}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: batch.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_upload_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l.noFilesSelected,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: batch.items.length,
                    itemBuilder: (context, index) {
                      final item = batch.items[index];
                      final isActive = index == activeIndex;
                      return _BatchRow(
                        item: item,
                        progress: isActive ? single.progress : null,
                        phase: isActive ? single.phase : null,
                        formatSize: _formatSize,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Выбор коллекции для пачки: одна коллекция на все файлы.
///
/// Создание новой — прямо отсюда (диалог выбора умеет и создавать):
/// иначе «выбрать коллекцию» при пустом списке коллекций бесполезно.
class _CollectionPicker extends StatelessWidget {
  const new({
    required this.name,
    required this.enabled,
    required this.onTap,
    required this.onClear,
  });

  final String? name;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name == null ? l.noCollection : '${l.collection}: $name',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (name != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: l.noCollection,
                  onPressed: enabled ? onClear : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка файла пачки: имя, размер и статус (прогресс — только
/// у активного, итоги — иконками, ошибка — текстом).
class _BatchRow extends StatelessWidget {
  const new({
    required this.item,
    required this.progress,
    required this.phase,
    required this.formatSize,
  });

  final BatchUploadItem item;
  final double? progress;
  final UploadPhase? phase;
  final String Function(int) formatSize;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (icon, color) = switch (item.status) {
      BatchItemStatus.pending => (Icons.schedule, Colors.grey),
      BatchItemStatus.active => (Icons.upload, null),
      BatchItemStatus.done => (Icons.check_circle, Colors.green),
      BatchItemStatus.duplicate => (Icons.copy_all, Colors.orange),
      BatchItemStatus.failed => (Icons.error_outline, Colors.red),
      BatchItemStatus.cancelled => (Icons.cancel_outlined, Colors.grey),
    };
    final statusText = switch (item.status) {
      BatchItemStatus.pending => l.queued,
      BatchItemStatus.active => _phaseLabel(l, phase) ?? l.uploading,
      BatchItemStatus.done => l.uploadSuccess,
      BatchItemStatus.duplicate =>
        item.existingTitle == null
            ? l.fileAlreadyExists
            : '${l.fileAlreadyExists}: ${item.existingTitle}',
      BatchItemStatus.failed => item.errorMessage ?? l.uploadFailed,
      BatchItemStatus.cancelled => l.uploadCancelled,
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.source.name, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatSize(item.fileSize)),
          if (item.status == BatchItemStatus.active && progress != null)
            LinearProgressIndicator(value: progress),
          Text(statusText),
        ],
      ),
    );
  }

  String? _phaseLabel(AppLocalizations l, UploadPhase? phase) {
    return switch (phase) {
      UploadPhase.hashing => l.hashingFile,
      UploadPhase.checking => l.checkingDuplicates,
      UploadPhase.uploading => l.uploading,
      UploadPhase.processing => l.serverProcessing,
      null => null,
    };
  }
}

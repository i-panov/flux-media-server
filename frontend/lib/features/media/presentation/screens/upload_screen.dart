import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/core/utils/scaffold_messenger.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class UploadScreen extends ConsumerStatefulWidget {
  const new({required this.mediaType, super.key});

  final String mediaType;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;

  String _formatSize(int bytes) {
    if (bytes > 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.mediaType == 'audio'
          ? ['mp3', 'flac', 'ogg', 'm4a', 'aac', 'wav', 'opus', 'wma']
          : ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v'],
    );

    if (result.isEmpty) return;
    final file = result.first;
    final path = file.path;
    if (path == null) return;

    // Размер читаем асинхронно: lengthSync() блокирует UI-изолят и на
    // крупном файле подвисает кадр (хеширование ради этого унесли в
    // Isolate.run — до файла добрались только здесь).
    final size = await File(path).length();
    if (!mounted) return;
    setState(() {
      _selectedFile = File(path);
      _selectedFileName = file.name;
      _selectedFileSize = size;
    });
  }

  void _cancelUpload() {
    ref.read(uploadControllerProvider.notifier).cancel();
  }

  Future<void> _startUpload() async {
    final file = _selectedFile;
    if (file == null) return;

    final l = AppLocalizations.of(context)!;
    final fileSize = _selectedFileSize ?? await file.length();
    if (!mounted) return;

    if (fileSize == 0) {
      _showSnackBar(l.uploadFileEmpty, Colors.red);
      return;
    }
    // Лимит — из контроллера, а не локальный хардкод: две копии дефолта
    // разъехались бы при первой же настройке.
    final maxSize = ref.read(uploadControllerProvider.notifier).maxUploadSizeBytes;
    if (fileSize > maxSize) {
      _showSnackBar(l.uploadFileTooLarge, Colors.red);
      return;
    }

    final started = await ref.read(uploadControllerProvider.notifier).start(
      filePath: file.path,
      mediaType: widget.mediaType,
      fileName: _selectedFileName,
      fileSize: fileSize,
      onSuccess: () => _onUploadSuccess(l),
    );
    if (!mounted) return;

    // Фидбек с явным цветом: зелёный — успех, красный/оранжевый —
    // ошибка и отмена. Экран мог размонтироваться во время загрузки.
    // errorMessage гарантирован контроллером на любом реальном сбое
    // (см. инвариант UploadState.errorMessage), поэтому ветка без
    // сообщения — это дубликат, а не замаскированная ошибка.
    final state = ref.read(uploadControllerProvider);
    if (state.cancelled) {
      _showSnackBar(l.uploadCancelled, Colors.orange);
    } else if (!started) {
      final message = state.errorMessage;
      if (message != null) {
        _showSnackBar(message, Colors.red);
      } else {
        _showSnackBar(l.fileAlreadyExists, Colors.orange);
      }
    }
  }

  Future<void> _onUploadSuccess(AppLocalizations l) async {
    // Контроллер мог завершить уже после ухода с экрана (autoDispose
    // прерывает poll, но гонка возможна): мёртвый контекст не трогаем.
    if (!context.mounted) return;
    refreshMediaLists(ref);
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(l.uploadSuccess),
        backgroundColor: Colors.green,
      ),
    );
    await context.router.maybePop();
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    showTextSnackBar(context, message, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(uploadControllerProvider);
    final progress = state.progress;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.uploadMedia),
        actions: [
          if (state.isUploading)
            IconButton(
              onPressed: _cancelUpload,
              icon: const Icon(Icons.close),
              tooltip: l.cancel,
            )
          else if (_selectedFile != null)
            TextButton.icon(
              onPressed: _startUpload,
              icon: const Icon(Icons.cloud_upload),
              label: Text(l.upload),
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),

          // File picker button.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.isUploading ? null : _pickFile,
                icon: Icon(
                  _selectedFile != null
                      ? Icons.check_circle
                      : Icons.attach_file,
                ),
                label: Text(
                  _selectedFileName ?? l.selectFiles,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),

          if (_selectedFileSize != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatSize(_selectedFileSize!),
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],

          if (state.isUploading) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  // Честный индикатор: детерминированный при известном
                  // размере, иначе — неопределённый спиннер.
                  if (progress != null)
                    LinearProgressIndicator(value: progress)
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_phaseLabel(state.phase) ?? l.uploading),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _cancelUpload,
                    icon: const Icon(Icons.close),
                    label: Text(l.cancel),
                  ),
                ],
              ),
            ),
          ],

          if (_selectedFile == null)
            Expanded(
              child: Center(
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
              ),
            ),
        ],
      ),
    );
  }

  String? _phaseLabel(UploadPhase? phase) {
    final l = AppLocalizations.of(context)!;
    return switch (phase) {
      UploadPhase.hashing => l.hashingFile,
      UploadPhase.checking => l.checkingDuplicates,
      UploadPhase.uploading => l.uploading,
      UploadPhase.processing => l.serverProcessing,
      null => null,
    };
  }
}

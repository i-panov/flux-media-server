import 'dart:io';
import 'dart:isolate';

import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_media.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({required this.mediaType, super.key});

  final String mediaType;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  /// Лимит сервера по умолчанию (configs/config.yaml: max_upload_size).
  static const _maxUploadSizeBytes = 2 * 1024 * 1024 * 1024;

  bool _isUploading = false;
  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;

  /// Флаг отмены: хэширование и загрузка прерываются.
  bool _cancelled = false;

  /// Прогресс загрузки (null, пока неизвестен размер).
  int? _sentBytes;
  int? _totalBytes;

  /// Троттлинг прогресса: setState на каждый ~64КБ chunk давал бы
  /// десятки тысяч rebuild'ов.
  static const _progressThrottle = Duration(milliseconds: 150);
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Текущая фаза: хэширование / проверка дубликата / загрузка.
  String? _phase;

  String _formatSize(int bytes) {
    if (bytes > 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.mediaType == 'audio'
          ? ['mp3', 'flac', 'ogg', 'm4a', 'aac', 'wav', 'opus', 'wma']
          : ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v'],
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() {
      _selectedFile = File(file.path!);
      _selectedFileName = file.name;
      _selectedFileSize = file.size;
    });
  }

  void _cancelUpload() {
    setState(() => _cancelled = true);
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _startUpload() async {
    final file = _selectedFile;
    if (file == null) return;

    final l = AppLocalizations.of(context)!;
    final fileSize = _selectedFileSize ?? await file.length();
    if (fileSize == 0) {
      _showSnackBar(l.uploadFileEmpty, Colors.red);
      return;
    }
    if (fileSize > _maxUploadSizeBytes) {
      _showSnackBar(
        l.uploadFileTooLarge,
        Colors.red,
      );
      return;
    }

    setState(() {
      _cancelled = false;
      _sentBytes = null;
      _totalBytes = null;
      _phase = l.hashingFile;
      _isUploading = true;
    });

    try {
      // SHA-256 в фоновом изоляте: на файлах в 2+ ГБ синхронное
      // хэширование в UI-изоляте замораживало интерфейс.
      final filePath = file.path;
      final hash = await Isolate.run(
        () async => sha256.bind(File(filePath).openRead()).first,
      );
      if (_cancelled) throw const _UploadCancelled();

      if (mounted) setState(() => _phase = l.checkingDuplicates);

      // Check duplicate — ошибка сети не должна молча превращаться
      // в «дубликатов нет»: показываем ошибку и прерываемся.
      final checkMediaHash = ref.read(checkMediaHashProvider);
      final checkResult = await checkMediaHash(hash.toString());
      final exists = checkResult.fold(
        (failure) {
          _showSnackBar(
            '${l.errorLabel}: ${failure.message}',
            Colors.red,
          );
          return null;
        },
        (data) => data.exists,
      );
      if (exists == null) return;
      if (_cancelled) throw const _UploadCancelled();

      if (exists) {
        _showSnackBar(l.fileAlreadyExists, Colors.orange);
        return;
      }

      if (mounted) setState(() => _phase = l.uploading);

      final uploadMedia = ref.read(uploadMediaProvider);
      final result = await uploadMedia(
        UploadMediaParams(
          filePath: file.path,
          mediaType: widget.mediaType,
          fileName: _selectedFileName!,
          onProgress: (sent, total) {
            // Троттлинг: финальное обновление проходим всегда.
            final now = DateTime.now();
            final isFinal = sent >= (total ?? sent);
            if (!isFinal &&
                now.difference(_lastProgressUpdate) < _progressThrottle) {
              return;
            }
            _lastProgressUpdate = now;
            if (mounted) {
              setState(() {
                _sentBytes = sent;
                _totalBytes = total;
              });
            }
          },
          isCancelled: () => _cancelled,
        ),
      );

      if (!mounted) return;

      if (_cancelled) {
        _showSnackBar(l.uploadCancelled, Colors.orange);
        return;
      }

      result.fold(
        (failure) {
          if (failure is UploadCancelledFailure) {
            _showSnackBar(l.uploadCancelled, Colors.orange);
            return;
          }
          _showSnackBar(l.failedToAdd(failure.message), Colors.red);
        },
        (_) {
          _showSnackBar(l.uploadSuccess, Colors.green);
          refreshMediaLists(ref);
          context.router.maybePop();
        },
      );
    } on _UploadCancelled {
      _showSnackBar(l.uploadCancelled, Colors.orange);
    } catch (e, st) {
      AppLogger.error('Upload failed', e, st);
      _showSnackBar(
        _cancelled ? l.uploadCancelled : l.failedToAdd(l.errorLabel),
        _cancelled ? Colors.orange : Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _phase = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final progress = (_totalBytes != null && _totalBytes! > 0)
        ? (_sentBytes ?? 0) / _totalBytes!
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.uploadMedia),
        actions: [
          if (_isUploading)
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
                onPressed: _isUploading ? null : _pickFile,
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

          if (_isUploading) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  // Честный индикатор: детерминированный при известном
                  // размере, иначе — неопределённый спиннер.
                  if (progress != null)
                    LinearProgressIndicator(value: progress.clamp(0.0, 1.0))
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_phase ?? l.uploading),
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
}

/// Внутренний маркер отмены (отличаем от сетевых ошибок).
class _UploadCancelled implements Exception {
  const _UploadCancelled();
}

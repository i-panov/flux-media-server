import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_media.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/library.dart';

@RoutePage()
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key, required this.mediaType});

  final String mediaType;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final List<_FileInfo> _selectedFiles = [];
  MediaLibrary? _selectedLibrary;
  bool _isUploading = false;
  int _uploadedCount = 0;
  int _totalCount = 0;
  int _skippedCount = 0;
  String? _statusText;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: widget.mediaType == 'audio'
          ? ['mp3', 'flac', 'ogg', 'm4a', 'aac', 'wav', 'opus', 'wma']
          : ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v'],
    );

    if (result == null || result.files.isEmpty) return;

    final l = AppLocalizations.of(context)!;
    final checkMediaHash = ref.read(checkMediaHashProvider);

    for (final file in result.files) {
      if (file.path == null) continue;
      if (file.size == 0) continue;

      setState(() => _statusText = l.checkingFile(file.name));

      final hash = await _computeHash(File(file.path!));

      if (!mounted) return;

      final checkResult = await checkMediaHash(hash);

      if (!mounted) return;

      final exists = checkResult.fold(
        (failure) {
          return false;
        },
        (data) => data.exists,
      );

      if (exists) {
        setState(() => _skippedCount++);
      } else {
        _selectedFiles.add(_FileInfo(
          path: file.path!,
          name: file.name,
          size: file.size,
          hash: hash,
          extension: file.extension,
        ));
      }
    }

    if (!mounted) return;
    setState(() => _statusText = null);
  }

  Future<String> _computeHash(File file) async {
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  Future<void> _startUpload() async {
    if (_selectedFiles.isEmpty || _selectedLibrary == null) return;

    final l = AppLocalizations.of(context)!;

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _totalCount = _selectedFiles.length;
      _statusText = l.uploading;
    });

    final uploadMedia = ref.read(uploadMediaProvider);
    var successCount = 0;
    String? firstError;

    for (final fileInfo in _selectedFiles) {
      try {
        final result = await uploadMedia(
          UploadMediaParams(
            filePath: fileInfo.path,
            libraryId: _selectedLibrary!.id,
            fileName: fileInfo.name,
          ),
        );

        if (!mounted) return;

        result.fold(
          (failure) => firstError ??= failure.message,
          (_) => successCount++,
        );
      } on TimeoutException {
        firstError ??= 'Upload timed out. The file may be too large or the connection is too slow.';
      } catch (e) {
        firstError ??= e.toString();
      }

      setState(() => _uploadedCount++);
    }

    setState(() {
      _isUploading = false;
      _statusText = null;
    });

    if (mounted) {
      final buffer = StringBuffer(l.uploadedOfTotal(successCount, _totalCount));
      if (_skippedCount > 0) {
        buffer.write(' (${l.skippedAlreadyExists(_skippedCount)})');
      }
      if (firstError != null) {
        buffer.write('\n${l.failedToAdd(firstError!)}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(buffer.toString()),
          backgroundColor: firstError == null && successCount == _totalCount
              ? Colors.green
              : Colors.orange,
        ),
      );

      if (successCount > 0) {
        ref.invalidate(mediaListProvider);
        context.router.maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final librariesAsync = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.uploadMedia),
        actions: [
          if (_selectedFiles.isNotEmpty && !_isUploading)
            Tooltip(
              message: l.upload,
              child: TextButton.icon(
                onPressed: _startUpload,
                icon: const Icon(Icons.cloud_upload),
                label: Text(l.upload),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Auto-select library based on mediaType.
          librariesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${l.errorLoadingLibraries}: $e'),
            ),
            data: (libraries) {
              // Filter libraries by media type and auto-select first.
              final filtered = libraries
                  .where((lib) => lib.type == widget.mediaType)
                  .toList();

              if (_selectedLibrary == null && filtered.isNotEmpty) {
                _selectedLibrary = filtered.first;
              }

              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.noLibrariesYet),
                );
              }

              // If only one library, no need to show selector.
              if (filtered.length == 1) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<MediaLibrary>(
                  value: _selectedLibrary,
                  decoration: InputDecoration(
                    labelText: l.libraries,
                    border: const OutlineInputBorder(),
                  ),
                  items: filtered
                      .map((lib) => DropdownMenuItem(
                            value: lib,
                            child: Text(lib.name),
                          ))
                      .toList(),
                  onChanged: _isUploading
                      ? null
                      : (lib) => setState(() => _selectedLibrary = lib),
                ),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child:             SizedBox(
              width: double.infinity,
              child: Tooltip(
                message: l.selectFiles,
                child: OutlinedButton.icon(
                  onPressed: _isUploading ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: Text(l.selectFiles),
                ),
              ),
            ),
          ),

          if (_statusText != null) ...[
            const SizedBox(height: 8),
            Text(_statusText!),
          ],

          if (_isUploading) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _totalCount > 0 ? _uploadedCount / _totalCount : 0,
                  ),
                  const SizedBox(height: 4),
                  Text(l.ofTotal(_uploadedCount, _totalCount)),
                ],
              ),
            ),
          ],

          if (_skippedCount > 0 && !_isUploading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                l.filesSkippedOnServer(_skippedCount),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),

          if (_selectedFiles.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _selectedFiles.length,
                itemBuilder: (context, index) {
                  final file = _selectedFiles[index];
                  final size = file.size;
                  final sizeStr = size > 1024 * 1024
                      ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
                      : '${(size / 1024).toStringAsFixed(1)} KB';

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        _iconForExtension(file.extension),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(sizeStr),
                      trailing: _isUploading
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: l.delete,
                              onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                            ),
                    ),
                  );
                },
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(l.noFilesSelected, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'webm':
        return Icons.movie;
      case 'mp3':
      case 'flac':
      case 'ogg':
      case 'm4a':
      case 'aac':
      case 'wav':
        return Icons.music_note;
      default:
        return Icons.insert_drive_file;
    }
  }
}

class _FileInfo {
  const _FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.hash,
    required this.extension,
  });

  final String path;
  final String name;
  final int size;
  final String hash;
  final String? extension;
}

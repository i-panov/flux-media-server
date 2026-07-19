import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';
import 'package:flux_media_server/features/media/data/datasources/upload_service.dart';
import 'package:flux_media_server/shared/models/library.dart';

@RoutePage()
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  List<PlatformFile> _selectedFiles = [];
  MediaLibrary? _selectedLibrary;
  bool _isUploading = false;
  int _uploadedCount = 0;
  int _totalCount = 0;
  String? _error;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
    );

    if (result != null) {
      setState(() {
        _selectedFiles = result.files;
        _error = null;
      });
    }
  }

  Future<void> _startUpload() async {
    if (_selectedFiles.isEmpty || _selectedLibrary == null) return;

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _totalCount = _selectedFiles.length;
      _error = null;
    });

    final uploadService = ref.read(uploadServiceProvider);
    int successCount = 0;

    for (final file in _selectedFiles) {
      if (file.path == null) continue;

      final result = await uploadService.uploadFile(
        file: File(file.path!),
        libraryId: _selectedLibrary!.id,
        onProgress: (sent, total) {
          // Could update per-file progress here.
        },
      );

      if (result.success) {
        successCount++;
      }

      setState(() {
        _uploadedCount++;
      });
    }

    setState(() {
      _isUploading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploaded $successCount of $_totalCount files'),
          backgroundColor: successCount == _totalCount ? Colors.green : Colors.orange,
        ),
      );

      if (successCount > 0) {
        context.router.maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final librariesAsync = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Media'),
        actions: [
          if (_selectedFiles.isNotEmpty && !_isUploading)
            TextButton.icon(
              onPressed: _startUpload,
              icon: const Icon(Icons.cloud_upload),
              label: Text('Upload (${_selectedFiles.length})'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Library selector.
          librariesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading libraries: $e'),
            ),
            data: (libraries) => Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<MediaLibrary>(
                value: _selectedLibrary,
                decoration: const InputDecoration(
                  labelText: 'Target Library',
                  border: OutlineInputBorder(),
                ),
                items: libraries.map((lib) {
                  return DropdownMenuItem(
                    value: lib,
                    child: Text('${lib.name} (${lib.path})'),
                  );
                }).toList(),
                onChanged: _isUploading ? null : (lib) {
                  setState(() => _selectedLibrary = lib);
                },
              ),
            ),
          ),

          // Pick files button.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading ? null : _pickFiles,
                icon: const Icon(Icons.attach_file),
                label: const Text('Select Files'),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Upload progress.
          if (_isUploading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _totalCount > 0 ? _uploadedCount / _totalCount : 0,
                  ),
                  const SizedBox(height: 8),
                  Text('Uploading $_uploadedCount of $_totalCount files...'),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Error display.
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          // Selected files list.
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
                      title: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(sizeStr),
                      trailing: _isUploading
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                setState(() {
                                  _selectedFiles = List.from(_selectedFiles)
                                    ..removeAt(index);
                                });
                              },
                            ),
                    ),
                  );
                },
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No files selected',
                      style: TextStyle(color: Colors.grey),
                    ),
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
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}

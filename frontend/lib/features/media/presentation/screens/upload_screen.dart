import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
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
      type: FileType.media,
    );

    if (result == null || result.files.isEmpty) return;

    final uploadService = ref.read(uploadServiceProvider);

    for (final file in result.files) {
      if (file.path == null) continue;
      if (file.size == 0) continue; // skip empty files

      setState(() => _statusText = 'Checking ${file.name}...');

      // Compute SHA-256 hash.
      final hash = await _computeHash(File(file.path!));

      // Check if file already exists on server.
      final check = await uploadService.checkHash(hash);

      if (check.exists) {
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

    setState(() => _statusText = null);
  }

  Future<String> _computeHash(File file) async {
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  Future<void> _startUpload() async {
    if (_selectedFiles.isEmpty || _selectedLibrary == null) return;

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _totalCount = _selectedFiles.length;
      _statusText = 'Uploading...';
    });

    final uploadService = ref.read(uploadServiceProvider);
    int successCount = 0;

    for (final fileInfo in _selectedFiles) {
      final result = await uploadService.uploadFile(
        file: File(fileInfo.path),
        libraryId: _selectedLibrary!.id,
      );

      if (result.success) successCount++;

      setState(() => _uploadedCount++);
    }

    setState(() {
      _isUploading = false;
      _statusText = null;
    });

    if (mounted) {
      final msg = StringBuffer('Uploaded $successCount of $_totalCount files');
      if (_skippedCount > 0) {
        msg.write(' ($_skippedCount skipped - already exists)');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.toString()),
          backgroundColor: successCount == _totalCount ? Colors.green : Colors.orange,
        ),
      );

      if (successCount > 0) context.router.maybePop();
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
                items: libraries.map((lib) => DropdownMenuItem(
                  value: lib,
                  child: Text(lib.name),
                )).toList(),
                onChanged: _isUploading ? null : (lib) => setState(() => _selectedLibrary = lib),
              ),
            ),
          ),

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
                  Text('$_uploadedCount of $_totalCount'),
                ],
              ),
            ),
          ],

          if (_skippedCount > 0 && !_isUploading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '$_skippedCount file(s) skipped (already on server)',
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
                              onPressed: () => setState(() => _selectedFiles.removeAt(index)),
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
                    Text('No files selected', style: TextStyle(color: Colors.grey)),
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

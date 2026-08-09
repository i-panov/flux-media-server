import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool _isUploading = false;
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

  Future<void> _startUpload() async {
    if (_selectedFile == null) return;

    final l = AppLocalizations.of(context)!;

    try {
      setState(() => _isUploading = true);

      // Compute hash for duplicate check.
      final stream = _selectedFile!.openRead();
      final hash = await sha256.bind(stream).first;

      // Check duplicate.
      final checkMediaHash = ref.read(checkMediaHashProvider);
      final checkResult = await checkMediaHash(hash.toString());
      final exists = checkResult.fold((_) => false, (data) => data.exists);

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.fileAlreadyExists),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final uploadMedia = ref.read(uploadMediaProvider);
      final result = await uploadMedia(
        UploadMediaParams(
          filePath: _selectedFile!.path,
          mediaType: widget.mediaType,
          fileName: _selectedFileName!,
        ),
      );

      if (!mounted) return;

      result.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.failedToAdd(failure.message)),
              backgroundColor: Colors.red,
            ),
          );
        },
        (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.uploadSuccess),
              backgroundColor: Colors.green,
            ),
          );
          ref
            ..invalidate(mediaListProvider('video'))
            ..invalidate(mediaListProvider('audio'));
          context.router.maybePop();
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.failedToAdd(l.errorLabel)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.uploadMedia),
        actions: [
          if (_selectedFile != null && !_isUploading)
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
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(l.uploading),
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

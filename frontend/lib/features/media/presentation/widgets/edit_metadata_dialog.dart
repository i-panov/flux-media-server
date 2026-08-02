import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/filename_parser.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

Future<void> showEditMetadataDialog(
  BuildContext context,
  WidgetRef ref,
  Media media,
) async {
  final l = AppLocalizations.of(context)!;

  final saved = await showDialog<Map<String, dynamic>?>(
    context: context,
    builder: (ctx) => _EditMetadataDialog(media: media, l: l),
  );

  if (saved == null) return;

  final result =
      await ref.read(mediaRepositoryProvider).updateMetadata(media.id, saved);

  result.fold(
    (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.errorLabel}: ${failure.message}')),
        );
      }
    },
    (updatedMedia) {
      ref
          .read(mediaDetailProvider(media.id).notifier)
          .updateMedia(updatedMedia);
      ref.invalidate(mediaListProvider('video'));
      ref.invalidate(mediaListProvider('audio'));
    },
  );
}

class _EditMetadataDialog extends StatefulWidget {
  const _EditMetadataDialog({required this.media, required this.l});

  final Media media;
  final AppLocalizations l;

  @override
  State<_EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<_EditMetadataDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _descriptionController;
  final _formKey = GlobalKey<FormState>();

  String? _originalFilename;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.media.title);
    _artistController = TextEditingController(text: widget.media.artist ?? '');
    _albumController = TextEditingController(text: widget.media.album ?? '');
    _genreController = TextEditingController(text: widget.media.genre ?? '');
    _yearController = TextEditingController(text: widget.media.year.toString());
    _descriptionController =
        TextEditingController(text: widget.media.description ?? '');
    _originalFilename = widget.media.filename.isNotEmpty
        ? widget.media.filename
        : null;
  }

  /// Parse the original filename to extract title and year, then fill
  /// the title and year fields (non-destructive).
  void _fillFromFilename() {
    if (_originalFilename == null) return;
    final parsed = FilenameParser.parse(_originalFilename!);
    if (parsed.title.isNotEmpty) {
      _titleController.text = parsed.title;
    }
    if (parsed.year != null) {
      _yearController.text = parsed.year.toString();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _collectData() {
    final data = <String, dynamic>{
      'title': _titleController.text.trim(),
    };
    if (_artistController.text.trim().isNotEmpty) {
      data['artist'] = _artistController.text.trim();
    }
    if (_albumController.text.trim().isNotEmpty) {
      data['album'] = _albumController.text.trim();
    }
    if (_genreController.text.trim().isNotEmpty) {
      data['genre'] = _genreController.text.trim();
    }
    final yearParsed = int.tryParse(_yearController.text.trim());
    if (yearParsed != null) {
      data['year'] = yearParsed;
    }
    if (_descriptionController.text.trim().isNotEmpty) {
      data['description'] = _descriptionController.text.trim();
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return AlertDialog(
      title: Text(l.editMetadata),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: l.name),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l.requiredField : null,
              ),
              TextFormField(
                controller: _artistController,
                decoration: InputDecoration(labelText: l.artist),
              ),
              TextFormField(
                controller: _albumController,
                decoration: InputDecoration(labelText: l.album),
              ),
              TextFormField(
                controller: _genreController,
                decoration: InputDecoration(labelText: l.genre),
              ),
              TextFormField(
                controller: _yearController,
                decoration: InputDecoration(labelText: l.year),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: l.description),
                maxLines: 3,
              ),

              // Original filename section (only shown if available).
              if (_originalFilename != null) ...[
                const SizedBox(height: 12),
                Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.insert_drive_file, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _originalFilename!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _fillFromFilename,
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(l.useFilename),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_collectData());
            }
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
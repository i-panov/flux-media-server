import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/filename_parser.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/usecases/update_metadata.dart';
import 'package:flux_media_server/features/media/presentation/providers/artists_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_image_url.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';

Future<void> showEditMetadataDialog(
  BuildContext context,
  WidgetRef ref,
  Media media,
) async {
  // Сохранение происходит внутри диалога: при ошибке сети введённые
  // значения не теряются (диалог остаётся открытым).
  await showDialog<void>(
    context: context,
    builder: (ctx) => _EditMetadataDialog(media: media),
  );
}

class _EditMetadataDialog extends ConsumerStatefulWidget {
  const _EditMetadataDialog({required this.media});

  final Media media;

  @override
  ConsumerState<_EditMetadataDialog> createState() =>
      _EditMetadataDialogState();
}

class _EditMetadataDialogState extends ConsumerState<_EditMetadataDialog> {
  late final TextEditingController _titleController;
  late final List<TextEditingController> _artistControllers;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _descriptionController;
  final _formKey = GlobalKey<FormState>();

  String? _originalFilename;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.media.title);
    _artistControllers = widget.media.artists.isNotEmpty
        ? widget.media.artists
            .map((a) => TextEditingController(text: a.name))
            .toList()
        : [TextEditingController()];
    _albumController = TextEditingController(text: widget.media.album ?? '');
    _genreController = TextEditingController(text: widget.media.genre ?? '');
    _yearController = TextEditingController(
      text: hasMediaYear(widget.media.year)
          ? widget.media.year.toString()
          : '',
    );
    _descriptionController =
        TextEditingController(text: widget.media.description ?? '');
    _originalFilename =
        widget.media.filename.isNotEmpty ? widget.media.filename : null;
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

  void _addArtistField() {
    setState(() {
      _artistControllers.add(TextEditingController());
    });
  }

  void _removeArtistField(int index) {
    setState(() {
      _artistControllers[index].dispose();
      _artistControllers.removeAt(index);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _artistControllers) {
      c.dispose();
    }
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Год: либо пусто, либо 4 цифры в диапазоне 1888..текущий+2.
  String? _validateYear(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final year = int.tryParse(text);
    if (year == null || text.length != 4) {
      return AppLocalizations.of(context)!.invalidYear;
    }
    final maxYear = DateTime.now().year + 2;
    if (year < 1888 || year > maxYear) {
      return AppLocalizations.of(context)!.invalidYear;
    }
    return null;
  }

  MetadataEdit _collectData() {
    final album = _albumController.text.trim();
    final genre = _genreController.text.trim();
    final description = _descriptionController.text.trim();
    return MetadataEdit(
      title: _titleController.text.trim(),
      artists: _artistControllers
          .map((c) => c.text.trim())
          .where((name) => name.isNotEmpty)
          .toList(),
      album: album.isEmpty ? null : album,
      genre: genre.isEmpty ? null : genre,
      // Валидатор гарантирует корректный год (или пусто).
      year: int.tryParse(_yearController.text.trim()),
      description: description.isEmpty ? null : description,
    );
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final updateMetadata = ref.read(updateMetadataProvider);
    final result = await updateMetadata(
      UpdateMetadataParams(
        mediaId: widget.media.id,
        edit: _collectData(),
      ),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    result.fold(
      (failure) {
        // Ошибка сети: остаёмся открытыми, значения не теряются.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.errorLabel}: ${failure.message}'),
            backgroundColor: Colors.red,
          ),
        );
      },
      (updatedMedia) {
        ref
            .read(mediaDetailProvider(widget.media.id).notifier)
            .updateMedia(updatedMedia);
        refreshMediaLists(ref);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final artistsAsync = ref.watch(artistsProvider);

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
              // --- Artists group ---
              const SizedBox(height: 8),
              artistsAsync.when(
                data: (artists) => _buildArtistsGroup(l, artists),
                loading: () => _buildArtistsGroup(l, const []),
                error: (_, __) => _buildArtistsGroup(l, const []),
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
                validator: _validateYear,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: l.description),
                maxLines: 3,
              ),

              // Original filename section (only shown if available).
              if (_originalFilename != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      size: 16,
                      color: Colors.grey[600],
                    ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
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
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? l.saving : l.save),
        ),
      ],
    );
  }

  /// Builds the group of artist fields with autocomplete and add/remove
  /// buttons.
  Widget _buildArtistsGroup(AppLocalizations l, List<Artist> allArtists) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(l.artists, style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: l.artist,
                onPressed: _addArtistField,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._artistControllers.asMap().entries.map((entry) {
            final index = entry.key;
            final controller = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ArtistField(
                controller: controller,
                allArtists: allArtists,
                onRemove: _artistControllers.length > 1
                    ? () => _removeArtistField(index)
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// A single artist text field with autocomplete dropdown.
class _ArtistField extends StatefulWidget {
  const _ArtistField({
    required this.controller,
    required this.allArtists,
    this.onRemove,
  });

  final TextEditingController controller;
  final List<Artist> allArtists;
  final VoidCallback? onRemove;

  @override
  State<_ArtistField> createState() => _ArtistFieldState();
}

class _ArtistFieldState extends State<_ArtistField> {
  /// FocusNode живёт в State: ранее создавался на каждый rebuild.
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<String>.empty();
        return widget.allArtists
            .where((a) => a.name.toLowerCase().contains(query))
            .map((a) => a.name)
            .take(10);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: const OutlineInputBorder(),
            suffixIcon: widget.onRemove != null
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onRemove,
                    visualDensity: VisualDensity.compact,
                  )
                : null,
          ),
        );
      },
    );
  }
}

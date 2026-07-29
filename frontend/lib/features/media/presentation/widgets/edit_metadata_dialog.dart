import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final titleController = TextEditingController(text: media.title);
  final artistController = TextEditingController(text: media.artist ?? '');
  final albumController = TextEditingController(text: media.album ?? '');
  final genreController = TextEditingController(text: media.genre ?? '');
  final yearController =
      TextEditingController(text: media.year.toString());
  final descriptionController =
      TextEditingController(text: media.description ?? '');
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.editMetadata),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: InputDecoration(labelText: l.name),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: artistController,
                decoration: InputDecoration(labelText: l.artist),
              ),
              TextFormField(
                controller: albumController,
                decoration: InputDecoration(labelText: l.album),
              ),
              TextFormField(
                controller: genreController,
                decoration: InputDecoration(labelText: l.genre),
              ),
              TextFormField(
                controller: yearController,
                decoration: InputDecoration(labelText: l.year),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(ctx).pop(true);
            }
          },
          child: Text(l.save),
        ),
      ],
    ),
  );

  if (saved != true) {
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    genreController.dispose();
    yearController.dispose();
    descriptionController.dispose();
    return;
  }

  final data = <String, dynamic>{
    'title': titleController.text.trim(),
  };
  if (artistController.text.trim().isNotEmpty) {
    data['artist'] = artistController.text.trim();
  }
  if (albumController.text.trim().isNotEmpty) {
    data['album'] = albumController.text.trim();
  }
  if (genreController.text.trim().isNotEmpty) {
    data['genre'] = genreController.text.trim();
  }
  final yearParsed = int.tryParse(yearController.text.trim());
  if (yearParsed != null) {
    data['year'] = yearParsed;
  }
  if (descriptionController.text.trim().isNotEmpty) {
    data['description'] = descriptionController.text.trim();
  }

  titleController.dispose();
  artistController.dispose();
  albumController.dispose();
  genreController.dispose();
  yearController.dispose();
  descriptionController.dispose();

  final result = await ref
      .read(mediaRepositoryProvider)
      .updateMetadata(media.id, data);

  result.fold(
    (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.errorLabel}: ${failure.message}')),
        );
      }
    },
    (_) {
      ref.invalidate(mediaDetailProvider(media.id));
    },
  );
}

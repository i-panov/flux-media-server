import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Создание коллекции: имя + тип.
///
/// Отдельный вход нужен не только из меню медиа: коллекцию должно быть
/// где создать и без файла — иначе при загрузке пачки нечего выбрать
/// (коллекции создавались только как побочка «добавить файл»).
///
/// Возвращает созданную коллекцию или null (отмена/ошибка).
Future<Collection?> showCreateCollectionDialog(
  BuildContext context, {
  required MediaType type,
}) {
  return showDialog<Collection>(
    context: context,
    builder: (_) => _CreateCollectionDialog(type: type),
  );
}

class _CreateCollectionDialog extends ConsumerStatefulWidget {
  const new({required this.type});

  final MediaType type;

  @override
  ConsumerState<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends ConsumerState<_CreateCollectionDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _canSubmit = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final canSubmit = _nameController.text.trim().isNotEmpty;
    if (canSubmit != _canSubmit) {
      setState(() => _canSubmit = canSubmit);
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final result = await ref
        .read(collectionsRepositoryProvider)
        .createCollection(name: name, type: widget.type.value);
    if (!mounted) return;
    result.fold(
      (failure) {
        setState(() => _submitting = false);
        final l = AppLocalizations.of(context)!;
        showErrorSnackBar(context, l.failedToCreate(failure.message));
      },
      (collection) {
        // Список коллекций инвалидируем здесь, а не у вызывающих: коллекция
        // создаётся из трёх мест (секция «Мои коллекции», диалог «добавить
        // в коллекцию», выбор коллекции при загрузке), и забыть об
        // инвалидации в одном из них означало бы, что коллекция появится
        // только после pull-to-refresh.
        ref.invalidate(collectionsProvider);
        Navigator.pop(context, collection);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.create),
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(labelText: l.name),
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: _canSubmit && !_submitting ? _submit : null,
          child: Text(l.create),
        ),
      ],
    );
  }
}

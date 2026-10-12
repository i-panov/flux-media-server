import 'package:flutter/material.dart';
import 'package:flux_media_server/core/utils/extensions.dart';

/// Диалог переименования артиста: возвращает обрезанное имя или null.
///
/// Вынесен из `ArtistPage` ради тестируемости валидации: пустое имя
/// и имя без изменений отклоняются вызывающей стороной, здесь только ввод.
/// Контроллер живёт в `State` и диспоузится вместе с диалогом — возврат
/// `showDialog`-future не означает, что роут уже размонтирован.
Future<String?> showRenameArtistDialog(
  BuildContext context,
  String currentName,
) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameArtistDialog(currentName: currentName),
  );
}

class _RenameArtistDialog extends StatefulWidget {
  const new({required this.currentName});

  final String currentName;

  @override
  State<_RenameArtistDialog> createState() => _RenameArtistDialogState();
}

class _RenameArtistDialogState extends State<_RenameArtistDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.editArtistName),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.artistName),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.save)),
      ],
    );
  }
}

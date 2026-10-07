import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ссылка на источник: иконка открывает ссылку в браузере, вторая
/// иконка копирует её в буфер обмена.
///
/// Показываем хост, а не полный URL: длинные ссылки обрезались в
/// `https://www.yout...` и были нечитаемы. Открытие закалено:
/// перепроверка схемы (в старом кеше может лежать `javascript:`),
/// try/catch вокруг `launchUrl` (без браузера — необработанный
/// `PlatformException`), снекбар во всех ветках.
class SourceLinkRow extends StatelessWidget {
  const new({required this.url, super.key});

  final String url;

  Future<void> _open(BuildContext context) async {
    // Валидация как в диалоге: кеш мог сохранить ссылку до ужесточения
    // правил или в обход них.
    if (!isValidHttpUrl(url)) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.cannotOpenLink,
        );
      }
      return;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.cannotOpenLink,
        );
      }
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      showErrorSnackBar(context, AppLocalizations.of(context)!.cannotOpenLink);
    }
  }

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.cannotOpenLink,
        );
      }
      return;
    }
    if (!context.mounted) return;
    showSuccessSnackBar(context, AppLocalizations.of(context)!.linkCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final host = Uri.tryParse(url.trim())?.host ?? url;
    return Semantics(
      label: '${l.sourceUrl}: $host',
      button: true,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _open(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        host.isEmpty ? url : host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            color: Colors.white70,
            tooltip: l.copyLink,
            onPressed: () => _copy(context),
          ),
        ],
      ),
    );
  }
}

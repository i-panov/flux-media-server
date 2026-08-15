import 'package:flutter/material.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Полноэкранный блок ошибки с кнопкой «Повторить».
/// Единая замена 3 дублирующих копий на экранах audio/video.
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    required this.onRetry,
    super.key,
    this.message,
    this.icon = Icons.error_outline,
  });

  final VoidCallback onRetry;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      ),
    );
  }
}

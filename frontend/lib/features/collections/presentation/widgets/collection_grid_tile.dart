import 'package:flutter/material.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Плитка медиа в сетке коллекции с кнопкой удаления элемента.
///
/// Вынесена из `CollectionDetailScreen` ради тестируемости: навигация
/// и подтверждение удаления — колбэки наружу, здесь только вёрстка.
class CollectionGridTile extends StatelessWidget {
  const new({
    required this.media,
    required this.onTap,
    required this.onRemove,
    this.onMove,
    super.key,
  });

  final Media media;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      children: [
        MediaCard(media: media, onTap: onTap),
        // Кнопка удаления элемента из коллекции (зона тапа 48dp).
        // Tooltip — он же семантический лейбл для скринридера.
        Positioned(
          top: 4,
          left: 4,
          child: Tooltip(
            message: l.removeFromCollection,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onRemove,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.playlist_remove,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Кнопка переноса элемента в другую коллекцию (справа сверху,
        // симметрично удалению слева). Нет обработчика — не рисуем.
        if (onMove != null)
          Positioned(
            top: 4,
            right: 4,
            child: Tooltip(
              message: l.moveToCollection,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: onMove,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.drive_file_move_outlined,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

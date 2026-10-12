import 'package:flutter/material.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
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
    super.key,
  });

  final Media media;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MediaCard(media: media, onTap: onTap),
        // Кнопка удаления элемента из коллекции (зона тапа 48dp).
        Positioned(
          top: 4,
          left: 4,
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
      ],
    );
  }
}

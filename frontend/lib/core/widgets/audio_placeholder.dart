import 'package:flutter/material.dart';

/// A programmatic placeholder for audio files without embedded cover art.
/// Draws a purple gradient background with a music note icon — no image file needed.
class AudioPlaceholder extends StatelessWidget {
  const AudioPlaceholder({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteColor = colorScheme.primary.withOpacity(0.5);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.surface,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.5,
          color: noteColor,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Circular card representing an artist for horizontal scroll display.
class ArtistCard extends StatelessWidget {
  const ArtistCard({
    required this.name,
    super.key,
    this.onTap,
  });

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: name,
      button: true,
      child: Column(
        children: [
          // Hover-отклик только на круге: подсветка и лёгкая тень не
          // должны «накрывать» подпись (на десктопе овал поверх текста).
          _ArtistAvatar(onTap: onTap),
          const SizedBox(height: 4),
          SizedBox(
            width: 80,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistAvatar extends StatefulWidget {
  const _ArtistAvatar({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<_ArtistAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? colorScheme.primaryContainer
                    .withValues(alpha: 0.7)
                : colorScheme.primaryContainer,
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.person,
            size: 40,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

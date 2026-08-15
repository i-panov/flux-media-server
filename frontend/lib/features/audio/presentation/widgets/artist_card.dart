import 'package:flutter/material.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';

/// Circular card representing an artist for horizontal scroll display.
class ArtistCard extends StatelessWidget {
  const ArtistCard({
    required this.name,
    super.key,
    this.onTap,
    this.coverUrl,
  });

  final String name;
  final VoidCallback? onTap;

  /// URL обложки артиста (null — обложки нет, показываем иконку).
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: name,
      button: true,
      child: Column(
        children: [
          // Hover-отклик только на круге: подсветка и лёгкая тень не
          // должны «накрывать» подпись (на десктопе овал поверх текста).
          _ArtistAvatar(onTap: onTap, coverUrl: coverUrl),
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
  const _ArtistAvatar({this.onTap, this.coverUrl});

  final VoidCallback? onTap;
  final String? coverUrl;

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
            color: colorScheme.primaryContainer,
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
          // Обложка, если есть; иначе — иконка-плейсхолдер.
          child: ClipOval(
            child: widget.coverUrl != null
                ? AuthNetworkImage(
                    imageUrl: widget.coverUrl!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _placeholder(colorScheme),
                    errorWidget: (_, __, ___) => _placeholder(colorScheme),
                  )
                : _placeholder(colorScheme),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.person,
        size: 40,
        color: colorScheme.primary,
      ),
    );
  }
}

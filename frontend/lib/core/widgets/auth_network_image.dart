import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';

/// A [CachedNetworkImage] that attaches the JWT access token as an
/// `Authorization` header. Required for protected endpoints
/// such as `/api/media/:id/thumb`.
class AuthNetworkImage extends ConsumerWidget {
  const AuthNetworkImage({
    required this.imageUrl,
    super.key,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token =
        ref.watch(settingsProvider.select((s) => s.settings.authToken));
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: token == null ? null : {'Authorization': 'Bearer $token'},
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}

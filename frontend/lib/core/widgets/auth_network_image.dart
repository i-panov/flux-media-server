import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';

/// A [CachedNetworkImage] that attaches the JWT access token as an
/// `Authorization` header. Required for protected endpoints
/// such as `/api/media/:id/thumb`.
class AuthNetworkImage extends ConsumerWidget {
  const new({
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
    final token = ref.watch(
      settingsProvider.select((s) => s.settings.authToken),
    );
    final baseUrl = ref.watch(
      settingsProvider.select((s) => s.settings.serverUrl),
    );
    final headers = shouldAttachAuthHeader(imageUrl, baseUrl, token)
        ? {'Authorization': 'Bearer $token'}
        : null;
    return CachedNetworkImage(
      // Пересоздание загрузки при смене токена: после refresh старый
      // 401-ответ не должен показываться навсегда.
      key: ValueKey<String?>(headers?['Authorization']),
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: headers,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}

/// Bearer-токен уходит только на хост приложения: для сторонних
/// URL (например, внешние обложки) авторизация не прикладывается.
///
/// Сравниваем и порт: один и тот же хост на другом порту — это другой
/// сервис, и отправлять ему наш токен нельзя. Относительные URL
/// отклоняем: без схемы и хоста сравнивать не с чем, а токен в таком
/// случае ушёл бы неизвестно куда.
bool shouldAttachAuthHeader(String imageUrl, String? baseUrl, String? token) {
  if (token == null || token.isEmpty) return false;
  if (baseUrl == null) return false;
  final image = Uri.tryParse(imageUrl);
  final base = Uri.tryParse(baseUrl);
  if (image == null || base == null) return false;
  if (!image.hasScheme || !base.hasScheme) return false;
  if (image.host.isEmpty || base.host.isEmpty) return false;
  return image.scheme == base.scheme &&
      image.host == base.host &&
      _portOf(image) == _portOf(base);
}

/// Порт с учётом схемы: отсутствующий порт — дефолтный для этой схемы.
/// Неизвестным схемам дефолта нет — возвращаем -1, чтобы они никогда не
/// совпали с чем-то осмысленным.
int _portOf(Uri uri) => uri.hasPort ? uri.port : _defaultPortOf(uri.scheme);

int _defaultPortOf(String scheme) => switch (scheme) {
  'https' => 443,
  'http' => 80,
  _ => -1,
};

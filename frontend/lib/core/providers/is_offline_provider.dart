import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';

/// True when the server is unreachable but we have stored credentials
/// (offline mode — show only downloaded content).
final isOfflineProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  return authState is AuthError;
});

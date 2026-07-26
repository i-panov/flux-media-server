import 'dart:io';

/// Whether the app is running inside WSL (Windows Subsystem for Linux).
/// WSL typically has no GPU passthrough, so hardware-accelerated video
/// rendering will crash.  The result is cached after the first call.
bool get isRunningInWSL => _isWSL ??= _detectWSL();

bool? _isWSL;

bool _detectWSL() {
  try {
    final version = File('/proc/version').readAsStringSync();
    final lower = version.toLowerCase();
    return lower.contains('microsoft') || lower.contains('wsl');
  } catch (_) {
    return false;
  }
}

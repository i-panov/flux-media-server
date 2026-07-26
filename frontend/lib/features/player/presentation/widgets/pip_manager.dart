import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Manages Picture-in-Picture mode.
/// On desktop: shows a floating overlay within the app.
/// On mobile (Android): enters system PiP mode via platform channel.
class PipManager {
  PipManager._();

  static OverlayEntry? _overlayEntry;
  static bool _isActive = false;

  static bool get isActive => _isActive;

  /// Enters PiP mode.
  /// [context] must be from the current video player screen.
  /// [videoController] is the media_kit controller for the video.
  static void enterPip({
    required BuildContext context,
    required VideoController videoController,
  }) {
    if (_isActive) return;

    // Try platform PiP first (Android/iOS)
    _tryPlatformPip().then((success) {
      if (!success) {
        // Fallback: in-app floating overlay (desktop)
        _showOverlayPip(context, videoController);
      }
    });
  }

  /// Tries to enter system PiP mode via platform channel.
  /// Returns true if successful.
  static Future<bool> _tryPlatformPip() async {
    try {
      const platform = MethodChannel('flux_media_server/pip');
      final result = await platform.invokeMethod<bool>('enterPipMode');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows an in-app floating video overlay (desktop fallback).
  static void _showOverlayPip(
    BuildContext context,
    VideoController videoController,
  ) {
    final overlay = Overlay.of(context);
    _isActive = true;

    _overlayEntry = OverlayEntry(
      builder: (context) => _PipOverlay(
        videoController: videoController,
        onClose: exitPip,
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  /// Exits PiP mode and removes the overlay.
  static void exitPip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isActive = false;
  }
}

/// Floating video overlay widget for desktop PiP.
class _PipOverlay extends StatefulWidget {
  const _PipOverlay({
    required this.videoController,
    required this.onClose,
  });

  final VideoController videoController;
  final VoidCallback onClose;

  @override
  State<_PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends State<_PipOverlay> {
  Offset _position = const Offset(50, 50);
  final _size = Size(320, 180);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: _size.width,
          height: _size.height,
          child: Stack(
            children: [
              Video(controller: widget.videoController),
              // Drag handle
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _position += details.delta;
                    });
                  },
                  child: Container(
                    height: 32,
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.drag_indicator, color: Colors.white, size: 16),
                        GestureDetector(
                          onTap: widget.onClose,
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

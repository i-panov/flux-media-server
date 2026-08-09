import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counter that increments every time a download completes or is removed.
/// `DownloadsNotifier` watches this to know when to refresh.
final downloadsInvalidatorProvider = StateProvider<int>((_) => 0);

// Riverpod 3: StateProvider — legacy API, импортируется из legacy.dart.
import 'package:flutter_riverpod/legacy.dart';

/// Counter that increments every time a download completes or is removed.
/// `DownloadsNotifier` watches this to know when to refresh.
final downloadsInvalidatorProvider = StateProvider<int>((_) => 0);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/library/data/datasources/library_remote_datasource.dart';
import 'package:flux_media_server/features/library/data/repositories/library_repository_impl.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

final libraryRemoteDataSourceProvider = Provider<LibraryRemoteDataSource>((ref) {
  return LibraryRemoteDataSource(ref.watch(apiClientProvider));
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepositoryImpl(ref.watch(libraryRemoteDataSourceProvider));
});

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<MediaLibrary>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<MediaLibrary>> {
  Timer? _pollTimer;
  int? _scanningLibraryId;

  @override
  Future<List<MediaLibrary>> build() async {
    final repo = ref.watch(libraryRepositoryProvider);
    final result = await repo.getLibraries();
    return result.fold(
      (failure) => throw Exception(failure.message),
      (libraries) => libraries,
    );
  }

  /// Triggers a scan and starts polling for status.
  Future<void> scan(int id) async {
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.scanLibrary(id);
    result.fold(
      (failure) => state = AsyncError(Exception(failure.message), StackTrace.current),
      (_) {
        _scanningLibraryId = id;
        _startPolling(id);
      },
    );
  }

  /// Starts polling scan status every 2 seconds.
  void _startPolling(int libraryId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkScanStatus(libraryId);
    });
  }

  /// Checks scan status and stops polling when scan completes.
  Future<void> _checkScanStatus(int libraryId) async {
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.getScanStatus(libraryId);
    result.fold(
      (failure) {
        // On error, stop polling and reload
        _stopPolling();
        ref.invalidateSelf();
      },
      (status) {
        if (!status.running) {
          _stopPolling();
          _scanningLibraryId = null;
          // Reload library list to reflect new media
          ref.invalidateSelf();
        }
        // Notify listeners about scan status change
        ref.notifyListeners();
      },
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Returns the current scan status for a library, or null if not scanning.
  /// This triggers a rebuild when scan status changes.
  ScanStatus? getScanStatus(int libraryId) {
    // This is called from the UI; the actual status is fetched async.
    // Return null — the UI should use [scanStatusProvider] for real-time status.
    return null;
  }

  /// Whether a scan is currently in progress.
  bool get isScanning => _scanningLibraryId != null;

  /// The ID of the library currently being scanned, or null.
  int? get scanningLibraryId => _scanningLibraryId;

  void refresh() {
    _stopPolling();
    ref.invalidateSelf();
  }

  /// Creates a new library.
  Future<String?> createLibrary({
    required String name,
    required String type,
  }) async {
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.createLibrary(name: name, type: type);
    return result.fold(
      (failure) => failure.message,
      (_) {
        ref.invalidateSelf();
        return null;
      },
    );
  }

  /// Deletes a library.
  Future<String?> deleteLibrary(int id) async {
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.deleteLibrary(id);
    return result.fold(
      (failure) => failure.message,
      (_) {
        ref.invalidateSelf();
        return null;
      },
    );
  }

  // Note: AsyncNotifier doesn't have dispose(). Cleanup is handled
  // by the provider framework via ref.onDispose if needed.
}

/// Provides real-time scan status by polling.
final scanStatusProvider = FutureProvider.family<ScanStatus?, int>((ref, libraryId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  final result = await repo.getScanStatus(libraryId);
  return result.fold(
    (failure) => null,
    (status) => status,
  );
});

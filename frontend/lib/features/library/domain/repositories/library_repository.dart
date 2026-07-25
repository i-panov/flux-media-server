import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

abstract class LibraryRepository {
  Future<Either<Failure, List<MediaLibrary>>> getLibraries();

  /// Triggers a scan and returns a status message.
  Future<Either<Failure, String>> scanLibrary(int id);

  /// Gets the current scan status for a library.
  Future<Either<Failure, ScanStatus>> getScanStatus(int id);

  /// Creates a new library.
  Future<Either<Failure, MediaLibrary>> createLibrary({
    required String name,
    required String type,
  });

  /// Deletes a library.
  Future<Either<Failure, void>> deleteLibrary(int id);
}

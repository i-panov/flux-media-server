import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/library/data/datasources/library_remote_datasource.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this.remoteDataSource);

  final LibraryRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<MediaLibrary>>> getLibraries() =>
      safeRepositoryCall(() async {
        final jsonList = await remoteDataSource.getLibraries();
        return jsonList.map((json) => MediaLibrary.fromJson(json)).toList();
      });

  @override
  Future<Either<Failure, String>> scanLibrary(int id) =>
      safeRepositoryCall(() => remoteDataSource.scanLibrary(id));

  @override
  Future<Either<Failure, ScanStatus>> getScanStatus(int id) =>
      safeRepositoryCall(() async {
        final json = await remoteDataSource.getScanStatus(id);
        return ScanStatus.fromJson(json);
      });

  @override
  Future<Either<Failure, MediaLibrary>> createLibrary({
    required String name,
    required String type,
  }) =>
      safeRepositoryCall(() async {
        final json = await remoteDataSource.createLibrary(name: name, type: type);
        return MediaLibrary.fromJson(json);
      });

  @override
  Future<Either<Failure, void>> deleteLibrary(int id) =>
      safeRepositoryCall(() => remoteDataSource.deleteLibrary(id));
}

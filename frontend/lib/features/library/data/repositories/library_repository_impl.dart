import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/library/data/datasources/library_remote_datasource.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this.remoteDataSource);

  final LibraryRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, List<MediaLibrary>>> getLibraries() async {
    try {
      final jsonList = await remoteDataSource.getLibraries();
      final libraries =
          jsonList.map((json) => MediaLibrary.fromJson(json)).toList();
      return Right(libraries);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, String>> scanLibrary(int id) async {
    try {
      final message = await remoteDataSource.scanLibrary(id);
      return Right(message);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, ScanStatus>> getScanStatus(int id) async {
    try {
      final json = await remoteDataSource.getScanStatus(id);
      return Right(ScanStatus.fromJson(json));
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, MediaLibrary>> createLibrary({
    required String name,
    required String type,
  }) async {
    try {
      final json = await remoteDataSource.createLibrary(
        name: name,
        type: type,
      );
      return Right(MediaLibrary.fromJson(json));
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deleteLibrary(int id) async {
    try {
      await remoteDataSource.deleteLibrary(id);
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }
}

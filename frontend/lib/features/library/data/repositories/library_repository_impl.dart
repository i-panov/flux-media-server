import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/library/data/datasources/library_remote_datasource.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';

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
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, MediaLibrary>> scanLibrary(int id) async {
    try {
      final json = await remoteDataSource.scanLibrary(id);
      return Right(MediaLibrary.fromJson(json));
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }
}

import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/collections/domain/repositories/collections_repository.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:fpdart/fpdart.dart';

class CreateCollectionParams {
  const CreateCollectionParams({required this.name, required this.type});
  final String name;
  final String type;
}

class CreateCollection
    extends UseCase<Either<Failure, Collection>, CreateCollectionParams> {
  CreateCollection(this.repository);
  final CollectionsRepository repository;

  @override
  Future<Either<Failure, Collection>> call(CreateCollectionParams params) {
    return repository.createCollection(name: params.name, type: params.type);
  }
}

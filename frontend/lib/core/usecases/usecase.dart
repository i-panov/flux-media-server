// ignore_for_file: one_member_abstracts, avoid_types_as_parameter_names

/// Base class for all use cases.
/// [Type] is the return type, [Params] is the input type.
abstract class UseCase<Type, Params> {
  Future<Type> call(Params params);
}

/// A marker class for use cases that don't require parameters.
class NoParams {
  const NoParams();
}

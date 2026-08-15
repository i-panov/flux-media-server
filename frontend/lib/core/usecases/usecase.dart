/// Base class for all use cases.
/// [TOutput] is the return type, [TInput] is the input type.
// ignore: one_member_abstracts
abstract class UseCase<TOutput, TInput> {
  Future<TOutput> call(TInput params);
}

/// A marker class for use cases that don't require parameters.
class NoParams {
  const NoParams();
}

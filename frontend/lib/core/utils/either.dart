import 'package:flux_media_server/core/error/failures.dart';

abstract class Either<L, R> {
  const Either();

  bool get isLeft => this is Left<L, R>;
  bool get isRight => this is Right<L, R>;

  T fold<T>(T Function(L) leftFn, T Function(R) rightFn) {
    if (isLeft) {
      return leftFn((this as Left<L, R>).value);
    }
    return rightFn((this as Right<L, R>).value);
  }

  Either<L, R2> map<R2>(R Function(R) fn) {
    if (isRight) {
      return Right(fn((this as Right<L, R>).value));
    }
    return this as Left<L, R2>;
  }
}

class Left<L, R> extends Either<L, R> {
  const Left(this.value);
  final L value;
}

class Right<L, R> extends Either<L, R> {
  const Right(this.value);
  final R value;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/shared/models/user.dart';

class FakeAuthRepository implements AuthRepository {
  Future<Either<Failure, String?>> Function(String)? onRequestCode;
  Future<Either<Failure, ({String token, User user})>> Function(String, String)?
      onVerifyCode;
  Future<Either<Failure, User>> Function()? onGetCurrentUser;

  @override
  Future<Either<Failure, String?>> requestCode(String email) =>
      onRequestCode!(email);

  @override
  Future<Either<Failure, ({String token, User user})>> verifyCode(
    String email,
    String code,
  ) =>
      onVerifyCode!(email, code);

  @override
  Future<Either<Failure, User>> getCurrentUser() => onGetCurrentUser!();
}

void main() {
  late AuthNotifier notifier;
  late FakeAuthRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeAuthRepository();
    notifier = AuthNotifier(
      requestCode: RequestCode(fakeRepo),
      verifyCode: VerifyCode(fakeRepo),
      getCurrentUser: GetCurrentUser(fakeRepo),
    );
  });

  tearDown(() {
    notifier.dispose();
  });

  group('AuthNotifier', () {
    test('initial state is AuthInitial', () {
      expect(notifier.state, isA<AuthInitial>());
    });

    group('requestCode', () {
      test('emits loading then codeSent with debug code', () async {
        fakeRepo.onRequestCode = (_) async => const Right('123456');

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.requestCode('test@example.com');

        // states: [initial, loading, codeSent]
        expect(states, hasLength(3));
        expect(states[1], isA<AuthLoading>());

        final codeSent = states[2] as AuthCodeSent;
        expect(codeSent.email, 'test@example.com');
        expect(codeSent.debugCode, '123456');
      });

      test('emits codeSent without debug code in production', () async {
        fakeRepo.onRequestCode = (_) async => const Right(null);

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.requestCode('test@example.com');

        final codeSent = states[2] as AuthCodeSent;
        expect(codeSent.debugCode, isNull);
      });

      test('emits error on failure', () async {
        fakeRepo.onRequestCode =
            (_) async => const Left(ServerFailure(message: 'Email not allowed'));

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.requestCode('test@example.com');

        expect(states[2], isA<AuthError>());
        expect((states[2] as AuthError).message, 'Email not allowed');
      });
    });

    group('verifyCode', () {
      test('emits authenticated on success', () async {
        final user = User(id: 1, email: 'test@example.com');
        fakeRepo.onVerifyCode = (_, __) async =>
            Right((token: 'jwt-token', user: user));

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.verifyCode('test@example.com', '123456');

        expect(states[2], isA<AuthAuthenticated>());
        expect((states[2] as AuthAuthenticated).user.email, 'test@example.com');
      });

      test('emits error on invalid code', () async {
        fakeRepo.onVerifyCode = (_, __) async =>
            const Left(ServerFailure(message: 'Invalid or expired code'));

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.verifyCode('test@example.com', '000000');

        expect(states[2], isA<AuthError>());
        expect((states[2] as AuthError).message, 'Invalid or expired code');
      });
    });

    group('checkAuthStatus', () {
      test('emits authenticated when token is valid', () async {
        final user = User(id: 1, email: 'test@example.com');
        fakeRepo.onGetCurrentUser = () async => Right(user);

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.checkAuthStatus();

        expect(states[2], isA<AuthAuthenticated>());
      });

      test('emits initial when token is invalid', () async {
        fakeRepo.onGetCurrentUser =
            () async => const Left(ServerFailure(message: 'Unauthorized'));

        final states = <AuthState>[];
        notifier.addListener(states.add);

        await notifier.checkAuthStatus();

        expect(states[2], isA<AuthInitial>());
      });
    });
  });
}

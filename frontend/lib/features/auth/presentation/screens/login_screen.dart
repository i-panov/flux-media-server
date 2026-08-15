import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// Клиентский cooldown: не даёт спамить requestCode.
  static const _requestCooldown = Duration(seconds: 30);

  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final ValueNotifier<int> _cooldown = ValueNotifier(0);
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Восстанавливаем email после возврата с экрана кода
    // (ошибка верификации, «изменить email»).
    final lastEmail = ref.read(authProvider.notifier).lastRequestedEmail;
    if (lastEmail != null && lastEmail.isNotEmpty) {
      _emailController.text = lastEmail;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldown.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldown.value = _requestCooldown.inSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown.value > 0) {
        _cooldown.value--;
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _requestCode() async {
    if (_isLoading || _cooldown.value > 0) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final sent = await ref.read(authProvider.notifier).requestCode(email);
    if (mounted) {
      setState(() => _isLoading = false);
      if (sent) {
        _startCooldown();
        await context.router.replace(
          CodeRoute(email: email),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 24),
                Text(
                  l.appTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l.enterEmailToSignIn,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l.email,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l.pleaseEnterEmail;
                    }
                    // Без ограничения длины TLD: {2,4} отсекает новые
                    // домены (например .technology); достаточно наличия
                    // хотя бы одной точки в доменной части.
                    if (!RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]+$')
                        .hasMatch(value)) {
                      return l.pleaseEnterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<int>(
                  valueListenable: _cooldown,
                  builder: (context, seconds, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed:
                            _isLoading || seconds > 0 ? null : _requestCode,
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : Text(
                                seconds > 0
                                    ? '${l.getCode} (${seconds}s)'
                                    : l.getCode,
                              ),
                      ),
                    );
                  },
                ),
                if (authState is AuthError) ...[
                  const SizedBox(height: 16),
                  Text(
                    authState.message,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () =>
                      context.router.replace(const ServerSetupRoute()),
                  child: Text(l.changeServer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

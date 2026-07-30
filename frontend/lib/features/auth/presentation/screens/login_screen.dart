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
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _requestCode() {
    if (_formKey.currentState!.validate()) {
      ref
          .read(authProvider.notifier)
          .requestCode(_emailController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    ref.listen(authProvider, (previous, next) {
      if (next is AuthCodeSent && previous is! AuthCodeSent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            // Replace (not push) so a resend triggered from CodeScreen
            // doesn't stack a second CodeScreen on top.
            context.router.replace(CodeRoute(
              email: next.email,
              debugCode: next.debugCode,
            ));
          } catch (_) {}
        });
      }
    });

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
                    if (!RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,4}$')
                        .hasMatch(value)) {
                      return l.pleaseEnterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: authState is AuthLoading ? null : _requestCode,
                    child: authState is AuthLoading
                        ? const CircularProgressIndicator()
                        : Text(l.getCode),
                  ),
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

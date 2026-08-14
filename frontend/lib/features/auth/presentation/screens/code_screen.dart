import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({
    required this.email,
    super.key,
  });

  final String email;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  /// Задержка перед повторной отправкой кода.
  static const _resendCooldown = Duration(seconds: 30);

  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Автозаполняем debug-код из актуального состояния провайдера,
    // а не из параметров конструктора.
    final state = ref.read(authProvider);
    if (state is AuthCodeSent && state.debugCode != null) {
      _codeController.text = state.debugCode!;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _verifyCode() {
    if (_formKey.currentState!.validate()) {
      ref.read(authProvider.notifier).verifyCode(
            widget.email,
            _codeController.text.trim(),
          );
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds > 0) {
          _cooldownSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  void _resendCode() {
    // Ресенд недоступен во время верификации и пока идёт cooldown.
    final state = ref.read(authProvider);
    if (state is AuthLoading || _cooldownSeconds > 0) return;
    ref.read(authProvider.notifier).requestCode(widget.email);
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(authProvider);
    final debugCode = authState is AuthCodeSent ? authState.debugCode : null;
    final isVerifying = authState is AuthLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.enterCode),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.mail_outline,
                  size: 64,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 24),
                Text(
                  l.checkYourEmail,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l.sentCodeTo(widget.email),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (debugCode != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bug_report, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          l.debugCodeLabel(debugCode),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    labelText: l.code,
                    border: const OutlineInputBorder(),
                    hintText: '000000',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l.pleaseEnterCode;
                    }
                    if (value.length != 6) {
                      return l.codeMustBe6Digits;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isVerifying ? null : _verifyCode,
                    child: isVerifying
                        ? const CircularProgressIndicator()
                        : Text(l.verify),
                  ),
                ),
                if (authState is AuthError) ...[
                  const SizedBox(height: 16),
                  Text(
                    authState.message,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed:
                      isVerifying || _cooldownSeconds > 0 ? null : _resendCode,
                  child: Text(
                    _cooldownSeconds > 0
                        ? '${l.resendCode} (${_cooldownSeconds}s)'
                        : l.resendCode,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

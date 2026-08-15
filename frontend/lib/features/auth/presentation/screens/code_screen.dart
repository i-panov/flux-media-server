import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
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

  /// Локальная загрузка верификации: глобальный AuthLoading размонтировал
  /// бы Navigator (splash) и потерял бы состояние экрана.
  bool _isVerifying = false;

  /// Debug-код из state на момент открытия экрана — переживает ошибку
  /// верификации (state в это время AuthError без debug-кода).
  String? _debugCode;

  final ValueNotifier<int> _cooldown = ValueNotifier(0);
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Автозаполняем debug-код из актуального состояния провайдера,
    // а не из параметров конструктора.
    final state = ref.read(authProvider);
    if (state is AuthCodeSent) {
      _debugCode = state.debugCode;
      if (state.debugCode != null) {
        _codeController.text = state.debugCode!;
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldown.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_isVerifying || !_formKey.currentState!.validate()) return;
    setState(() => _isVerifying = true);
    await ref
        .read(authProvider.notifier)
        .verifyCode(widget.email, _codeController.text.trim());
    // При успехе FluxApp уводит на MainRoute и экран размонтируется.
    if (mounted) setState(() => _isVerifying = false);
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldown.value = _resendCooldown.inSeconds;
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

  Future<void> _resendCode() async {
    if (_cooldown.value > 0 || _isVerifying) return;
    final sent =
        await ref.read(authProvider.notifier).requestCode(widget.email);
    if (!mounted) return;
    // Cooldown — только если код реально отправлен; при ошибке (в т.ч.
    // сетевой) не блокируем повторную попытку.
    if (sent) _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(authProvider);

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
                if (_debugCode != null) ...[
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
                          l.debugCodeLabel(_debugCode!),
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
                  autofocus: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    // allow() вместо digitsOnly: пропускает вставку из
                    // буфера обмена (digitsOnly блокирует вставку).
                    FilteringTextInputFormatter.allow(RegExp(r'\d{0,6}')),
                  ],
                  onFieldSubmitted: (_) => _verifyCode(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    labelText: l.code,
                    border: const OutlineInputBorder(),
                    hintText: '000000',
                    counterText: '',
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
                    onPressed: _isVerifying ? null : _verifyCode,
                    child: _isVerifying
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
                ValueListenableBuilder<int>(
                  valueListenable: _cooldown,
                  builder: (context, seconds, _) {
                    final enabled = seconds == 0 && !_isVerifying;
                    return Semantics(
                      label: l.resendCode,
                      enabled: enabled,
                      button: true,
                      child: TextButton(
                        onPressed: enabled ? _resendCode : null,
                        child: Text(
                          seconds > 0
                              ? '${l.resendCode} (${seconds}s)'
                              : l.resendCode,
                        ),
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () =>
                      context.router.replace(const LoginRoute()),
                  child: Text(l.changeEmail),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

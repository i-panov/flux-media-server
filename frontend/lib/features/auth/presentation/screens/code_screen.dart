import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/cooldown_button.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Форматтер поля OTP-кода: только цифры.
///
/// Вынесен на уровень файла, чтобы контракт «буквы не проходят» был
/// зафиксирован тестом, а не копией регулярки в нём.
final codeInputFormatter = FilteringTextInputFormatter.allow(RegExp('[0-9]'));

@RoutePage()
class CodeScreen extends ConsumerStatefulWidget {
  const new({required this.email, super.key});

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

  /// Не даёт спамить повторную отправку кода.
  final _cooldown = CooldownController(_resendCooldown);

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

  Future<void> _resendCode() async {
    if (_cooldown.isActive || _isVerifying) return;
    final sent = await ref
        .read(authProvider.notifier)
        .requestCode(widget.email);
    if (!mounted) return;
    // Cooldown — только если код реально отправлен; при ошибке (в т.ч.
    // сетевой) не блокируем повторную попытку.
    if (sent) _cooldown.start();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(authProvider);

    // Новый debug-код после resend: _debugCode из initState иначе
    // показывал бы stale-код от первой отправки. Поле ввода не трогаем,
    // если пользователь уже что-то набрал.
    ref.listen(authProvider, (_, next) {
      if (next is AuthCodeSent && next.debugCode != null && mounted) {
        setState(() {
          _debugCode = next.debugCode;
          if (_codeController.text.isEmpty) {
            _codeController.text = next.debugCode!;
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l.enterCode)),
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
                  inputFormatters: [codeInputFormatter],
                  onFieldSubmitted: (_) => _verifyCode(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: InputDecoration(
                    labelText: l.code,
                    border: const OutlineInputBorder(),
                    hintText: '000000',
                    counterText: '',
                    // Крупная тач-зона: целевой размер 48dp, не сжимаем.
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
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
                CooldownTextButton(
                  cooldown: _cooldown,
                  onPressed: _resendCode,
                  enabled: !_isVerifying,
                  label: l.resendCode,
                ),
                TextButton(
                  onPressed: () => context.router.replace(const LoginRoute()),
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

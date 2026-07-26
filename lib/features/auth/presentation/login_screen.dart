import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/widgets/app_button.dart';
import 'forgot_password_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isRegister = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _rememberSession = true;

  @override
  void initState() {
    super.initState();
    _loadRememberedLoginId();
  }

  Future<void> _loadRememberedLoginId() async {
    try {
      final savedId = await LocalStorage.instance.getCacheValue(
        'remembered_login_id',
        scoped: false,
      );
      if (savedId != null && savedId.isNotEmpty && mounted) {
        setState(() {
          _loginIdCtrl.text = savedId;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _loginIdCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    final loginId = _loginIdCtrl.text.trim();
    if (loginId.isNotEmpty) {
      try {
        await LocalStorage.instance.setCacheValue(
          'remembered_login_id',
          loginId,
          scoped: false,
        );
      } catch (_) {}
    }

    final auth = ref.read(authStateNotifierProvider.notifier);
    setState(() => _isSubmitting = true);

    try {
      if (_isRegister) {
        await auth.register(
          name: _nameCtrl.text.trim(),
          loginId: loginId,
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await auth.login(
          loginId: loginId,
          password: _passwordCtrl.text,
          rememberSession: _rememberSession,
        );
      }

      if (!mounted) return;

      final state = ref.read(authStateNotifierProvider);
      final hasError =
          state.maybeWhen(error: (_, __) => true, orElse: () => false);
      if (!hasError) {
        TextInput.finishAutofillContext();
      }
      state.whenOrNull(
        error: (error, _) {
          // Campos preservados — usuario nao precisa redigitar
          final message = _friendlyAuthError(error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
            ),
          );
        },
      );
    } catch (error) {
      // Erro inesperado — mostra mensagem sem limpar campos
      if (mounted) {
        final message = _friendlyAuthError(error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _openForgotPassword() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => const ForgotPasswordSheet(),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Senha redefinida com sucesso! Insira suas novas credenciais.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  static final _emailRe = RegExp(
    r"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.\-]{1,64}"
    r'@'
    r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*'
    r'\.[a-zA-Z]{2,}$',
  );

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Informe o e-mail';
    }
    if (!_emailRe.hasMatch(text)) {
      return 'E-mail invalido';
    }
    return null;
  }

  String? _validateLoginId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Informe o ID';
    }

    if (text.contains('@')) {
      return null;
    }

    final loginIdPattern = RegExp(
      r'^[a-zA-Z0-9](?:[a-zA-Z0-9._-]{1,38}[a-zA-Z0-9])?$',
    );
    if (!loginIdPattern.hasMatch(text)) {
      return 'Use 3-40 caracteres: letras, numeros, ponto, _ ou -';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isSubmitting;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.18),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/quiz_vance_logo_1024.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: -0.3, end: 0),
                      const SizedBox(height: 16),
                      Text(
                        'Quiz Vance',
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                      ).animate().fadeIn(delay: 200.ms),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? 'Crie sua conta com um ID de acesso'
                            : 'Entre com seu ID ou e-mail',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ).animate().fadeIn(delay: 300.ms),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isRegister) ...[
                        _buildLabel('Nome'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameCtrl,
                          autofillHints: const [AutofillHints.name],
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Seu nome completo',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe seu nome';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildLabel(
                        _isRegister ? 'ID de acesso' : 'ID de acesso ou e-mail',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _loginIdCtrl,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: _isRegister
                            ? TextInputAction.next
                            : TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: _isRegister
                              ? 'ex.: belchior.vance'
                              : 'Digite seu ID ou e-mail',
                          helperText: _isRegister
                              ? 'Voce usara esse ID para entrar na sua conta'
                              : null,
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        validator: _validateLoginId,
                      ),
                      const SizedBox(height: 16),
                      if (_isRegister) ...[
                        _buildLabel('E-mail'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailCtrl,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'seu@email.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildLabel('Senha'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        autofillHints: [
                          _isRegister
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.visiblePassword,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: '********',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe a senha';
                          }
                          if (value.length < 6) {
                            return 'Minimo 6 caracteres';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                if (!_isRegister)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _rememberSession,
                    onChanged: isLoading
                        ? null
                        : (value) => setState(
                              () => _rememberSession = value ?? true,
                            ),
                    title: const Text('Lembrar meu login'),
                    subtitle: const Text(
                      'Mantenha sua sessao neste aparelho.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                const SizedBox(height: 32),
                AppButton(
                  label: _isRegister ? 'Criar conta' : 'Entrar',
                  isLoading: isLoading,
                  onPressed: _submit,
                ),
                if (!_isRegister) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading ? null : _openForgotPassword,
                      child: const Text('Esqueci minha senha'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: isLoading
                        ? null
                        : () => setState(() => _isRegister = !_isRegister),
                    child: Text(
                      _isRegister
                          ? 'Ja tenho conta -> Entrar'
                          : 'Nao tenho conta -> Criar conta',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ].animate(interval: 80.ms).fadeIn().slideX(begin: 0.05, end: 0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
    );
  }

  String _friendlyAuthError(Object error) {
    final message = userVisibleErrorMessage(
      error,
      fallback: 'ID de acesso ou senha incorretos. Verifique suas credenciais.',
    );
    if (message.contains('DioException') ||
        message.contains('Exception') ||
        message.contains('Error')) {
      return 'ID de acesso ou senha incorretos. Verifique suas credenciais.';
    }
    return message;
  }
}

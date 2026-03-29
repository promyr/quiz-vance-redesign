import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/widgets/app_button.dart';
import 'forgot_password_sheet.dart';

const _sharedBackendUrl = 'https://quiz-vance-redesign-backend.fly.dev';

String backendHostLabel(String backendUrl) {
  final uri = Uri.tryParse(backendUrl);
  final host = uri?.host;
  if (host != null && host.isNotEmpty) {
    return host;
  }
  return backendUrl;
}

bool usesSharedBackend(String backendUrl) => backendUrl == _sharedBackendUrl;

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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _loginIdCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(authStateNotifierProvider.notifier);

    if (_isRegister) {
      await auth.register(
        name: _nameCtrl.text.trim(),
        loginId: _loginIdCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } else {
      await auth.login(
        loginId: _loginIdCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    }

    final state = ref.read(authStateNotifierProvider);
    if (!mounted) return;
    state.whenOrNull(
      error: (err, _) {
        // Exibe a mensagem do erro sem expor detalhes técnicos internos.
        // Erros do backend (DioException com detail) já chegam com mensagem
        // legível; para outros casos, usamos mensagem genérica.
        final msg = _friendlyAuthError(err);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  Future<void> _openForgotPassword() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => const ForgotPasswordSheet(),
    );
  }

  // Mesma regex usada no backend (services.py) — consistência cliente/servidor.
  static final _emailRe = RegExp(
    r"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.\-]{1,64}"
    r'@'
    r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*'
    r'\.[a-zA-Z]{2,}$',
  );

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe o e-mail';
    if (!_emailRe.hasMatch(text)) return 'E-mail inválido';
    return null;
  }

  String? _validateLoginId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe o ID';
    final isEmail = text.contains('@');
    if (isEmail) return null;

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
    final authState = ref.watch(authStateNotifierProvider);
    final isLoading = authState.isLoading;
    const backendUrl = AppConfig.backendUrl;
    final sharedBackend = usesSharedBackend(backendUrl);
    final backendLabel = backendHostLabel(backendUrl);

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
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: -0.3, end: 0),
                      const SizedBox(height: 16),
                      Text(
                        'Quiz Vance',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(color: AppColors.textPrimary),
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
                if (_isRegister) ...[
                  _buildLabel('Nome'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Seu nome completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe seu nome'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                _buildLabel(_isRegister ? 'ID de acesso' : 'ID ou e-mail'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _loginIdCtrl,
                  textInputAction:
                      _isRegister ? TextInputAction.next : TextInputAction.done,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: _isRegister
                        ? 'ex.: belchior.vance'
                        : 'Seu ID ou e-mail',
                    helperText: _isRegister
                        ? 'Será o dado principal para fazer login'
                        : 'Use o mesmo backend entre dispositivos para compartilhar a conta',
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
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Informe a senha';
                    if (v.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
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
                    onPressed: () => setState(() => _isRegister = !_isRegister),
                    child: Text(
                      _isRegister
                          ? 'Já tenho conta → Entrar'
                          : 'Não tenho conta → Criar conta',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sharedBackend
                        ? AppColors.primary.withOpacity(0.06)
                        : AppColors.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sharedBackend
                          ? AppColors.primary.withOpacity(0.18)
                          : AppColors.warning.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Servidor: $backendLabel',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (!sharedBackend) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Este app não está no backend compartilhado. Contas criadas em outro dispositivo podem não aparecer aqui.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ],
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
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppColors.textSecondary),
    );
  }

  /// Converte um erro de auth em mensagem amigável para o usuário.
  /// Extrai o campo `detail` de respostas HTTP quando disponível,
  /// sem expor stack traces ou detalhes técnicos internos.
  String _friendlyAuthError(Object err) {
    final raw = err.toString();
    // Mensagens curtas e legíveis do backend chegam diretamente
    if (raw.length <= 120 &&
        !raw.contains('Exception') &&
        !raw.contains('Error')) {
      return raw;
    }
    return 'Não foi possível entrar. Verifique seus dados e tente novamente.';
  }
}

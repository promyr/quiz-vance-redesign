import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/auth_repository.dart';
import '../data/login_biometric_vault.dart';
import 'forgot_password_sheet.dart';

enum AuthScreenMode {
  sessionUnlock,
  standardLogin,
}

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
  final _passwordFocusNode = FocusNode();

  bool _isInitializing = true;
  bool _isRegister = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _rememberSession = true;
  bool _canAuthenticate = false;
  bool _enrollBiometrics = true;
  Map<String, dynamic>? _savedUser;
  bool _biometricReady = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedLoginId();
  }

  Future<void> _loadRememberedLoginId() async {
    try {
      final repository = ref.read(authRepositoryProvider);
      final cached = await repository.getCachedUser();
      final biometrics = ref.read(loginBiometricAuthCoordinatorProvider);
      final biometricReady =
          await biometrics.canUnlock().catchError((_) => false);
      final canAuthenticate =
          await biometrics.canAuthenticate().catchError((_) => false);
      String? savedId;
      try {
        savedId = await LocalStorage.instance.getCacheValue(
          'remembered_login_id',
          scoped: false,
        );
      } catch (_) {
        // O cache auxiliar não pode esconder uma sessão válida.
      }

      final loginIdToUse = (savedId != null && savedId.isNotEmpty)
          ? savedId
          : (cached?['login_id']?.toString() ?? cached?['id']?.toString());

      if (mounted) {
        setState(() {
          _savedUser = cached;
          _biometricReady = biometricReady;
          _canAuthenticate = canAuthenticate;
          _enrollBiometrics = canAuthenticate && !biometricReady;
          if (loginIdToUse != null && loginIdToUse.isNotEmpty) {
            _loginIdCtrl.text = loginIdToUse;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _focusPassword() {
    _passwordFocusNode.requestFocus();
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_isSubmitting) return;
    if (!_biometricReady) {
      _focusPassword();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authStateNotifierProvider.notifier).loginWithBiometrics(
            loginId: _loginIdCtrl.text.trim(),
          );
      if (!mounted) return;
      final authState = ref.read(authStateNotifierProvider);
      authState.whenOrNull(
        error: (error, _) {
          final message = _friendlyBiometricError(error);
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () => messenger.clearSnackBars(),
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_friendlyBiometricError(error)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () => messenger.clearSnackBars(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        final biometricReady = await ref
            .read(loginBiometricAuthCoordinatorProvider)
            .canUnlock()
            .catchError((_) => false);
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _biometricReady = biometricReady;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _loginIdCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) {
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
          enrollBiometrics: _enrollBiometrics || _biometricReady,
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
          final message = _friendlyAuthError(error);
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () => messenger.clearSnackBars(),
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (mounted) {
        final message = _friendlyAuthError(error);
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () => messenger.clearSnackBars(),
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

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isSubmitting;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Background Glow Elements ─────────────────────────────────
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Content Scroll View ──────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    // ── Brand & Hero Section ─────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.4),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                'assets/quiz_vance_logo_1024.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 500.ms)
                              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1), curve: Curves.easeOutBack),
                          const SizedBox(height: 16),
                          Text(
                            'Quiz Vance',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ).animate().fadeIn(delay: 150.ms),
                          const SizedBox(height: 6),
                          Text(
                            _isRegister
                                ? 'Crie sua conta com um ID de acesso'
                                : 'Entre com seu ID ou e-mail',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ).animate().fadeIn(delay: 250.ms),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Tab Switcher (Entrar / Cadastrar) ─────────────────
                    if (!_isInitializing)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.border.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildAuthTab(
                                label: 'Entrar',
                                isSelected: !_isRegister,
                                onTap: () {
                                  if (_isRegister) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _isRegister = false;
                                      _formKey.currentState?.reset();
                                    });
                                  }
                                },
                              ),
                            ),
                            Expanded(
                              child: _buildAuthTab(
                                label: 'Cadastrar-se',
                                isSelected: _isRegister,
                                onTap: () {
                                  if (!_isRegister) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _isRegister = true;
                                      _formKey.currentState?.reset();
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 200.ms),

                    if (_isInitializing)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      )
                    else
                      _buildStandardLoginForm(context, isLoading),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textMuted,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardLoginForm(BuildContext context, bool isLoading) {
    final firstName = _savedUser != null
        ? (_savedUser!['name']?.toString().split(' ').first ??
            _savedUser!['login_id']?.toString())
        : null;

    return AutofillGroup(
      key: const Key('standard_login_form'),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.border.withOpacity(0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_biometricReady && !_isRegister) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                child: ElevatedButton.icon(
                  key: const Key('biometric_login_button'),
                  onPressed: isLoading ? null : _authenticateWithBiometrics,
                  icon: const Icon(Icons.fingerprint_rounded, size: 28, color: Colors.white),
                  label: Text(
                    firstName != null
                        ? 'Entrar com digital como $firstName'
                        : 'Entrar com digital',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                    shadowColor: AppColors.primary.withOpacity(0.4),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.border.withOpacity(0.6))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'ou entre com sua senha',
                      style: TextStyle(
                        color: AppColors.textMuted.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.border.withOpacity(0.6))),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_isRegister) ...[
              _buildLabel('Nome'),
              TextFormField(
                controller: _nameCtrl,
                autofillHints: const [AutofillHints.name],
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Seu nome completo',
                  filled: true,
                  fillColor: AppColors.background.withOpacity(0.6),
                  prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
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
            TextFormField(
              key: const Key('login_id_field'),
              controller: _loginIdCtrl,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: _isRegister
                    ? 'ex.: belchior.vance'
                    : 'Digite seu ID ou e-mail',
                helperText: _isRegister
                    ? 'Você usará esse ID para entrar na sua conta'
                    : null,
                helperStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                filled: true,
                fillColor: AppColors.background.withOpacity(0.6),
                prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
              validator: _validateLoginId,
            ),
            const SizedBox(height: 16),
            if (_isRegister) ...[
              _buildLabel('E-mail'),
              TextFormField(
                controller: _emailCtrl,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'seu@email.com',
                  filled: true,
                  fillColor: AppColors.background.withOpacity(0.6),
                  prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 16),
            ],
            _buildLabel('Senha'),
            TextFormField(
              key: const Key('login_password_field'),
              controller: _passwordCtrl,
              focusNode: _passwordFocusNode,
              obscureText: _obscurePassword,
              autofillHints: [
                _isRegister
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.visiblePassword,
              onFieldSubmitted: (_) => _submit(),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '********',
                filled: true,
                fillColor: AppColors.background.withOpacity(0.6),
                prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe a senha';
                }
                if (_isRegister && value.length < 6) {
                  return 'A senha deve ter no mínimo 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            if (!_isRegister) ...[
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberSession,
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      side: BorderSide(color: AppColors.border.withOpacity(0.8), width: 1.5),
                      onChanged: (value) => setState(
                        () => _rememberSession = value ?? true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Lembrar meu login',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _openForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Esqueci minha senha',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (_canAuthenticate && !_biometricReady) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        key: const Key('enroll_biometrics_checkbox'),
                        value: _enrollBiometrics,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        side: BorderSide(color: AppColors.border.withOpacity(0.8), width: 1.5),
                        onChanged: (value) => setState(
                          () => _enrollBiometrics = value ?? true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Acessar com digital nos próximos logins',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
            ] else ...[
              const SizedBox(height: 12),
            ],
            AppButton(
              label: _isRegister ? 'Criar conta' : 'Entrar',
              isLoading: isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isRegister ? 'Já tem uma conta?' : 'Não tem uma conta?',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _isRegister = !_isRegister;
                      _formKey.currentState?.reset();
                    }),
                    child: Text(
                      _isRegister ? 'Entrar' : 'Cadastrar-se',
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  String _friendlyAuthError(dynamic error) {
    if (error == null) return 'Ocorreu um erro ao realizar a operação.';
    if (error is RemoteServiceException) {
      return translateApiErrorMessage(error.message);
    }
    return translateApiErrorMessage(error.toString());
  }

  String _friendlyBiometricError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('not_enrolled') || msg.contains('nenhuma biometria')) {
      return 'Nenhuma biometria cadastrada no dispositivo.';
    }
    if (msg.contains('locked_out') || msg.contains('bloqueado')) {
      return 'Muitas tentativas. Use sua senha para entrar.';
    }
    if (msg.contains('canceled') || msg.contains('cancelado')) {
      return 'Autenticação por biometria cancelada.';
    }
    return 'Não foi possível autenticar por biometria. Digite sua senha.';
  }
}

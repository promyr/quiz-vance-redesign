import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/auth_repository.dart';

class ForgotPasswordSheet extends ConsumerStatefulWidget {
  const ForgotPasswordSheet({super.key});

  @override
  ConsumerState<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  final _identifierCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _requestSent = false;
  bool _isSubmitting = false;
  bool _isSuccess = false;
  String _successMessage = '';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final identifier = _identifierCtrl.text.trim();
    if (identifier.isEmpty) {
      _showMessage('Informe seu ID ou e-mail.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final message = await ref.read(authRepositoryProvider).requestPasswordReset(
            identifier: identifier,
          );
      if (!mounted) return;
      setState(() => _requestSent = true);
      _showMessage(message);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_errorMessage(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _confirmReset() async {
    final identifier = _identifierCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    if (identifier.isEmpty) {
      _showMessage('Informe seu ID ou e-mail.', isError: true);
      return;
    }
    if (code.isEmpty) {
      _showMessage('Informe o código recebido no e-mail.', isError: true);
      return;
    }
    if (password.length < 6) {
      _showMessage('A nova senha precisa ter no mínimo 6 caracteres.', isError: true);
      return;
    }
    if (password != confirmPassword) {
      _showMessage('As senhas não conferem.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final message = await ref.read(authRepositoryProvider).confirmPasswordReset(
            identifier: identifier,
            code: code,
            newPassword: password,
          );
      if (!mounted) return;
      setState(() {
        _isSuccess = true;
        _successMessage = message;
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage(_errorMessage(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
      }
      return userVisibleErrorMessage(error, fallback: 'Falha ao redefinir a senha.');
    }
    return userVisibleErrorMessage(error, fallback: 'Falha ao redefinir a senha.');
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: _isSuccess
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0x2210B981),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Senha redefinida com sucesso!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _successMessage.isNotEmpty
                        ? _successMessage
                        : 'Sua senha foi atualizada. Você já pode fazer login com suas novas credenciais.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: 28),
                  AppButton(
                    label: 'Fazer Login',
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: 12),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recuperar senha',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _requestSent
                        ? 'Digite o código recebido no e-mail e escolha a nova senha.'
                        : 'Informe seu ID ou e-mail para receber um código de redefinição.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _identifierCtrl,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'ID ou e-mail',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_requestSent) ...[
                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Código recebido',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Nova senha',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordCtrl,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirmar nova senha',
                        prefixIcon: const Icon(Icons.lock_person_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: 'Redefinir senha',
                      isLoading: _isSubmitting,
                      onPressed: _confirmReset,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _isSubmitting ? null : _requestCode,
                        child: const Text('Reenviar código'),
                      ),
                    ),
                  ] else ...[
                    AppButton(
                      label: 'Enviar código',
                      isLoading: _isSubmitting,
                      onPressed: _requestCode,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

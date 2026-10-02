part of 'profile_screen.dart';

class _ChangeLoginIdSheet extends ConsumerStatefulWidget {
  const _ChangeLoginIdSheet({
    required this.currentLoginId,
  });

  final String currentLoginId;

  @override
  ConsumerState<_ChangeLoginIdSheet> createState() =>
      _ChangeLoginIdSheetState();
}

class _ChangeLoginIdSheetState extends ConsumerState<_ChangeLoginIdSheet> {
  late final TextEditingController _loginIdCtrl;
  late final TextEditingController _currentPasswordCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _checking = false;
  bool _saving = false;
  String? _availabilityMessage;
  bool? _isAvailable;

  static final RegExp _loginIdPattern = RegExp(
    r'^[a-zA-Z0-9](?:[a-zA-Z0-9._-]{1,38}[a-zA-Z0-9])?$',
  );

  @override
  void initState() {
    super.initState();
    _loginIdCtrl = TextEditingController(text: widget.currentLoginId);
    _currentPasswordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _loginIdCtrl.dispose();
    _currentPasswordCtrl.dispose();
    super.dispose();
  }

  String? _validateLoginId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe o novo ID';
    if (!_loginIdPattern.hasMatch(text)) {
      return 'Use 3-40 caracteres: letras, numeros, ponto, _ ou -';
    }
    return null;
  }

  Future<void> _checkAvailability() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _checking = true;
      _availabilityMessage = null;
    });

    try {
      final result = await ref
          .read(authStateNotifierProvider.notifier)
          .checkLoginIdAvailability(_loginIdCtrl.text.trim());
      if (!mounted) return;

      setState(() {
        _isAvailable = result.available;
        _availabilityMessage = result.isCurrent
            ? 'Esse ja e o seu ID atual.'
            : result.available
                ? 'ID disponivel para uso.'
                : 'Esse ID ja esta em uso.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isAvailable = false;
        _availabilityMessage = 'Nao foi possivel verificar a disponibilidade.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(authStateNotifierProvider.notifier).updateLoginId(
            loginId: _loginIdCtrl.text.trim(),
            currentPassword: _currentPasswordCtrl.text,
          );
      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ID atualizado. Entre novamente para proteger sua conta.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving &&
        !_checking &&
        _currentPasswordCtrl.text.isNotEmpty &&
        (_isAvailable == true ||
            _loginIdCtrl.text.trim() == widget.currentLoginId);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Alterar ID da conta',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Seu ID e usado para login e exibicao. Verifique a disponibilidade antes de salvar.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _loginIdCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Novo ID',
                hintText: 'ex.: belchior.vance',
                border: OutlineInputBorder(),
              ),
              validator: _validateLoginId,
              onChanged: (_) {
                if (_availabilityMessage != null || _isAvailable != null) {
                  setState(() {
                    _availabilityMessage = null;
                    _isAvailable = null;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currentPasswordCtrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Senha atual',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Informe sua senha atual'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            if (_availabilityMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _availabilityMessage!,
                style: TextStyle(
                  color: (_isAvailable ?? false)
                      ? AppColors.success
                      : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _checking || _saving ? null : _checkAvailability,
                    child: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verificar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSave ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _passwordCtrl = TextEditingController();
  final _confirmationCtrl = TextEditingController();
  bool _deleting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmationCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    final confirmation = _confirmationCtrl.text.trim().toUpperCase();
    if (_passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe sua senha atual.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (confirmation != 'EXCLUIR') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite EXCLUIR para confirmar.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _deleting = true);
    try {
      await ref.read(authStateNotifierProvider.notifier).deleteAccount(
            currentPassword: _passwordCtrl.text,
            confirmationText: _confirmationCtrl.text.trim(),
          );
      if (!mounted) return;

      Navigator.of(context).pop();
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta excluida com sucesso.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Excluir conta',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Essa acao e irreversivel. Informe sua senha atual e digite EXCLUIR para confirmar.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Senha atual',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmationCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Digite EXCLUIR',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _deleting ? null : _deleteAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Excluir conta'),
            ),
          ),
        ],
      ),
    );
  }
}

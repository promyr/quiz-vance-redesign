part of 'login_screen.dart';

extension _LoginUnlockPanel on _LoginScreenState {
  Widget _buildSessionUnlockPanel(bool isLoading) {
    final name = _savedUser?['name']?.toString().trim() ?? _savedLoginId;
    final firstName = name.isEmpty ? _savedLoginId : name.split(' ').first;
    final avatar = _savedUser?['avatar_url']?.toString();
    return Container(
      key: const Key('session_unlock_panel'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primary.withOpacity(0.18),
              foregroundImage: avatar != null && avatar.isNotEmpty
                  ? NetworkImage(avatar)
                  : null,
              child: const Icon(Icons.person,
                  color: AppColors.primaryLight, size: 36),
            ),
          ),
          const SizedBox(height: 12),
          Text(name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('@$_savedLoginId',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 24),
          _buildLabel('Senha'),
          TextFormField(
            key: const Key('login_password_field'),
            controller: _passwordCtrl,
            focusNode: _passwordFocusNode,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onTap: _biometricReady && !isLoading
                ? _authenticateWithBiometrics
                : null,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Digite sua senha',
              filled: true,
              fillColor: AppColors.background.withOpacity(0.6),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: _togglePasswordVisibility,
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Informe a senha' : null,
          ),
          const SizedBox(height: 20),
          AppButton(
            key: Key(_biometricReady
                ? 'biometric_login_button'
                : 'unlock_login_button'),
            label: 'Continuar como $firstName',
            icon: _biometricReady ? Icons.fingerprint : Icons.lock_open,
            isLoading: isLoading,
            onPressed: () {
              if (_biometricReady && _passwordCtrl.text.isEmpty) {
                _authenticateWithBiometrics();
              } else {
                _submit();
              }
            },
          ),
          TextButton(
            onPressed: isLoading ? null : _openForgotPassword,
            child: const Text('Esqueci minha senha'),
          ),
          TextButton.icon(
            key: const Key('use_another_account'),
            onPressed: isLoading
                ? null
                : () => _setScreenMode(AuthScreenMode.standardLogin),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Usar outra conta'),
          ),
        ],
      ),
    );
  }
}

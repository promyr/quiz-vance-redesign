enum AdminStepUpScope {
  createAiKey('ai_key.create'),
  updateAiKey('ai_key.update'),
  deleteAiKey('ai_key.delete'),
  testAiKey('ai_key.test'),
  reorderAiKeys('ai_key.reorder');

  const AdminStepUpScope(this.value);

  final String value;
}

class AdminAuthorization {
  const AdminAuthorization._(this.headers);

  factory AdminAuthorization.password(String password) {
    if (password.isEmpty) {
      throw const FormatException('Informe a senha administrativa');
    }
    return AdminAuthorization._({'X-Admin-Password': password});
  }

  factory AdminAuthorization.biometric(String stepUpToken) {
    final value = stepUpToken.trim();
    if (value.isEmpty) {
      throw const FormatException('Autorização biométrica inválida');
    }
    return AdminAuthorization._({'X-Admin-Step-Up': value});
  }

  final Map<String, String> headers;
}

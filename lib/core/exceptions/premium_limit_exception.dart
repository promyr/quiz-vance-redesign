/// Exceção lançada quando um usuário free atinge o limite de uso de uma feature.
///
/// Capturada pelas telas de configuração para exibir o upsell contextual
/// em vez de uma mensagem de erro genérica.
class PremiumLimitException implements Exception {
  const PremiumLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

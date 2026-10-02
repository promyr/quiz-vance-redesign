import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sinal neutro de troca da sessão ativa.
///
/// Providers com dados vinculados à conta observam este contador para
/// reconstruir seu estado sem criar dependências de volta para autenticação.
class AccountSessionEpochNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state++;
}

final accountSessionEpochProvider =
    NotifierProvider<AccountSessionEpochNotifier, int>(
  AccountSessionEpochNotifier.new,
);

void markAccountSessionChanged(Ref ref) {
  ref.read(accountSessionEpochProvider.notifier).advance();
}

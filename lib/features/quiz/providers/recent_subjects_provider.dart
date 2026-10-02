import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/account_scoped_preferences.dart';

const String _kRecentSubjectsKey = 'recent_subjects';
const int _kMaxRecentSubjects = 20;

class RecentSubjectsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    return _loadRecentSubjects();
  }

  Future<List<String>> _loadRecentSubjects() async {
    final list = await AccountScopedPreferences.instance
        .getStringList(_kRecentSubjectsKey);
    return list ?? const <String>[];
  }

  /// Adiciona uma matéria/tópico à lista de recentes da conta ativa.
  /// Se já existir (comparação sem diferenciar maiúsculas/minúsculas), move para o topo.
  Future<void> addSubject(String rawSubject) async {
    final trimmed = rawSubject.trim();
    if (trimmed.length < 2) return;

    final current = state.value ?? await _loadRecentSubjects();
    final updated = List<String>.of(current);

    // Remove duplicatas case-insensitive
    updated.removeWhere(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    );

    // Insere no topo (mais recente)
    updated.insert(0, trimmed);

    // Limita tamanho máximo
    if (updated.length > _kMaxRecentSubjects) {
      updated.removeRange(_kMaxRecentSubjects, updated.length);
    }

    state = AsyncData(updated);
    await AccountScopedPreferences.instance.setStringList(
      _kRecentSubjectsKey,
      updated,
    );
  }

  /// Remove uma matéria específica da lista de recentes.
  Future<void> removeSubject(String subject) async {
    final current = state.value ?? await _loadRecentSubjects();
    final updated = current
        .where((item) => item.toLowerCase() != subject.trim().toLowerCase())
        .toList();

    state = AsyncData(updated);
    await AccountScopedPreferences.instance.setStringList(
      _kRecentSubjectsKey,
      updated,
    );
  }

  /// Limpa todas as matérias recentes da conta ativa.
  Future<void> clearAll() async {
    state = const AsyncData(<String>[]);
    await AccountScopedPreferences.instance.remove(_kRecentSubjectsKey);
  }
}

final recentSubjectsProvider =
    AsyncNotifierProvider<RecentSubjectsNotifier, List<String>>(
  RecentSubjectsNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';

import '../data/library_repository.dart';
import '../domain/library_model.dart';

enum OfflinePrefetchStatus { idle, prefetching, ready, error }

class OfflinePrefetchResult {
  const OfflinePrefetchResult({
    required this.status,
    required this.fileId,
    this.message,
  });

  final OfflinePrefetchStatus status;
  final int fileId;
  final String? message;

  bool get isReady => status == OfflinePrefetchStatus.ready;
}

class OfflinePackagePrefetcher {
  OfflinePackagePrefetcher({
    required LibraryRepository repository,
    AccountScopedPreferences? preferences,
  })  : _repository = repository,
        _preferences = preferences ?? AccountScopedPreferences.instance;

  final LibraryRepository _repository;
  final AccountScopedPreferences _preferences;

  static const _offlineFlagPrefix = 'offline_ready_file_';

  Future<bool> isPackageAvailableOffline(int fileId) async {
    final flag = await _preferences.getBool('$_offlineFlagPrefix$fileId');
    return flag ?? true; // Files in SQLite are available offline by default
  }

  Future<OfflinePrefetchResult> preparePackageForOffline({
    required LibraryFile file,
  }) async {
    try {
      // Ensure file content is saved in SQLite
      await _repository.addFile(
        nome: file.nome,
        conteudo: file.conteudo,
        categoria: file.categoria,
      );

      await _preferences.setBool('$_offlineFlagPrefix${file.id}', true);

      return OfflinePrefetchResult(
        status: OfflinePrefetchStatus.ready,
        fileId: file.id,
        message: 'Pacote preparado para estudo offline!',
      );
    } catch (error) {
      return OfflinePrefetchResult(
        status: OfflinePrefetchStatus.error,
        fileId: file.id,
        message: 'Erro ao preparar para offline: $error',
      );
    }
  }
}

final offlinePackagePrefetcherProvider = Provider<OfflinePackagePrefetcher>(
  (ref) => OfflinePackagePrefetcher(
    repository: ref.watch(libraryRepositoryProvider),
  ),
);

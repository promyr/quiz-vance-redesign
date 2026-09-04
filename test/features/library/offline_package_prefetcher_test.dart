import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/library/application/offline_package_prefetcher.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

void main() {
  late _MockLibraryRepository repository;
  late OfflinePackagePrefetcher prefetcher;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId(null);
    repository = _MockLibraryRepository();

    prefetcher = OfflinePackagePrefetcher(
      repository: repository,
      preferences: AccountScopedPreferences.instance,
    );
  });

  test('preparePackageForOffline saves file to repository and sets flag', () async {
    final file = LibraryFile(
      id: 101,
      nome: 'Direito Constitucional',
      categoria: 'Direito',
      conteudo: 'Artigo 1o...',
      criadoEm: DateTime.now(),
    );

    when(() => repository.addFile(
          nome: any(named: 'nome'),
          conteudo: any(named: 'conteudo'),
          categoria: any(named: 'categoria'),
        )).thenAnswer((_) async => file);

    final result = await prefetcher.preparePackageForOffline(file: file);

    expect(result.isReady, isTrue);
    expect(result.fileId, 101);

    final isAvailable = await prefetcher.isPackageAvailableOffline(101);
    expect(isAvailable, isTrue);
  });
}

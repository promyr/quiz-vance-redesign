import '../../../core/content/study_material_sanitizer.dart';
import 'material_scope_store.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/application/account_scoped_preferences.dart';
import '../domain/library_model.dart';
import '../domain/study_package_filter.dart';
import '../../study_plan/domain/study_document.dart';

class LibraryRepository {
  const LibraryRepository(this._client);

  final ApiClient _client;

  static const _legacyStorageKey = 'library_files';
  static const _migrationFlagKey = 'library_files_migrated_v2';

  Future<List<LibraryFile>> listFiles() async {
    await _migrateLegacyIfNeeded();
    final rows = await LocalStorage.instance.listLibraryFiles();

    return rows
        .map((entry) {
          try {
            return LibraryFile.fromJson(entry);
          } catch (_) {
            return null;
          }
        })
        .whereType<LibraryFile>()
        .toList();
  }

  Future<LibraryFile> addFile({
    required String nome,
    required String conteudo,
    String? categoria,
  }) async {
    await _migrateLegacyIfNeeded();

    final file = LibraryFile(
      id: DateTime.now().millisecondsSinceEpoch,
      nome: nome,
      categoria: categoria ?? 'Geral',
      conteudo: conteudo,
      criadoEm: DateTime.now(),
    );

    await LocalStorage.instance.upsertLibraryFile(file.toJson());
    return file;
  }

  Future<void> importProcessedDocument({
    required StudyDocument document,
    required String content,
  }) async {
    final accountId = AccountScopedPreferences.instance.activeAccountId;
    final deletionKey = _documentDeletionKey(document.id);
    await _migrateLegacyIfNeeded();
    final normalizedContent = content.trim();
    if (document.purpose != StudyDocumentPurpose.library ||
        document.status != StudyDocumentStatus.ready ||
        normalizedContent.isEmpty) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    // Recheck immediately before upsert: recovery may have downloaded the text
    // while the user deleted the item or switched to another account.
    if (preferences.getBool(deletionKey) == true ||
        AccountScopedPreferences.instance.activeAccountId != accountId) {
      return;
    }
    final normalizedName = document.fileName
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
        .trim();
    final file = LibraryFile(
      id: -document.id.abs(),
      nome: normalizedName.isEmpty ? 'Material em PDF' : normalizedName,
      categoria: 'Geral',
      conteudo: normalizedContent,
      criadoEm: DateTime.now(),
    );
    await LocalStorage.instance.upsertLibraryFile(file.toJson());
  }

  Future<void> deleteFile(int id) async {
    final accountId = AccountScopedPreferences.instance.activeAccountId;
    final deletionKey = _documentDeletionKey(id.abs());
    await _migrateLegacyIfNeeded();
    if (id < 0) {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(deletionKey, true);
      if (!saved) {
        throw StateError('Não foi possível salvar a exclusão do material.');
      }
    }
    if (AccountScopedPreferences.instance.activeAccountId != accountId) return;
    await LocalStorage.instance.deleteLibraryFile(id);
  }

  /// Exclusion is local to this account and installation, including offline.
  /// Uploading the PDF again creates a new server ID and permits a new import.
  Future<bool> isDocumentDeleted(int documentId) async {
    final key = _documentDeletionKey(documentId);
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) == true;
  }

  String _documentDeletionKey(int documentId) =>
      AccountScopedPreferences.instance.scopedKey(
        'library_deleted_document:$documentId',
      );

  Future<void> _migrateLegacyIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyMigrated = prefs.getBool(_migrationFlagKey) ?? false;
    if (alreadyMigrated) return;

    final raw = prefs.getString(_legacyStorageKey);
    if (raw == null || raw.trim().isEmpty || raw == '[]') {
      await prefs.setBool(_migrationFlagKey, true);
      await prefs.remove(_legacyStorageKey);
      return;
    }

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await prefs.setBool(_migrationFlagKey, true);
      await prefs.remove(_legacyStorageKey);
      return;
    }

    final files = decoded
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          try {
            return LibraryFile.fromJson(entry);
          } catch (_) {
            return null;
          }
        })
        .whereType<LibraryFile>()
        .map((file) => file.toJson())
        .toList();

    // Migracao nao-destrutiva: preserva arquivos atuais e apenas aplica upsert
    // dos itens legados que ainda existem no SharedPreferences.
    for (final file in files) {
      await LocalStorage.instance.upsertLibraryFile(file);
    }

    await prefs.setBool(_migrationFlagKey, true);
    await prefs.remove(_legacyStorageKey);
  }

  Future<StudyPackage> generatePackage({
    required LibraryFile file,
    String? aiProvider,
    List<String>? avoidFronts,
  }) async {
    try {
      final scoped = await MaterialScopeStore().resolve(file);
      file = scoped.file;
      final context = scoped.restricted
          ? scoped.promptContext(3200)
          : sanitizeStudyMaterialForPrompt(file.conteudo);
      if (scoped.restricted && context.trim().isEmpty) {
        throw StateError(
            "O trecho selecionado não contém conteúdo legível para gerar. Revise a seleção.");
      }

      final response = await _client.dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: {
          'topic': file.nome,
          'level': 'intermediario',
          'context': context,
          if (aiProvider != null && aiProvider.isNotEmpty)
            'provider': aiProvider,
          if (avoidFronts != null && avoidFronts.isNotEmpty)
            'avoid_fronts': avoidFronts,
        },
      );

      final package =
          StudyPackage.fromJson(response.data as Map<String, dynamic>);
      return sanitizeStudyPackageForMaterial(package: package, file: file);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(error.response?.data);

      if (detail != null) {
        if (statusCode >= 400 && statusCode < 500) {
          throw Exception(detail);
        }
        throw RemoteServiceException(detail);
      }

      if (statusCode >= 400 && statusCode < 500) {
        throw Exception('Erro $statusCode ao gerar pacote de estudos');
      }

      throw buildRemoteServiceException(
        error,
        fallback:
            'Não foi possível gerar o pacote de estudos agora. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor do pacote de estudos. Verifique sua conexão e tente novamente.',
      );
    }
  }
}

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(apiClientProvider)),
);

final libraryFilesProvider =
    FutureProvider.autoDispose<List<LibraryFile>>((ref) async {
  return ref.watch(libraryRepositoryProvider).listFiles();
});

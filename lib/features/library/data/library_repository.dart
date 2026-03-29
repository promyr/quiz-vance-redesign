import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/content/study_material_sanitizer.dart';
import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/storage/local_storage.dart';
import '../domain/library_model.dart';
import '../domain/study_package_filter.dart';

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

  Future<void> deleteFile(int id) async {
    await _migrateLegacyIfNeeded();
    await LocalStorage.instance.deleteLibraryFile(id);
  }

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
  }) async {
    try {
      final context = sanitizeStudyMaterialForPrompt(file.conteudo);

      final response = await _client.dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: {
          'topic': file.nome,
          'level': 'intermediario',
          'context': context,
          if (aiProvider != null && aiProvider.isNotEmpty)
            'provider': aiProvider,
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

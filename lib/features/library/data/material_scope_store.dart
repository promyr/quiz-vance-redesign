import '../../../core/content/study_material_sanitizer.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/application/account_scoped_preferences.dart';
import '../domain/library_model.dart';
import '../domain/material_chapters.dart';

class ScopedLibraryMaterial {
  const ScopedLibraryMaterial(this.file, this.restricted,
      {this.chapterTexts = const []});
  final LibraryFile file;
  final bool restricted;
  final List<String> chapterTexts;
  String promptContext(int maxChars) {
    if (!restricted || chapterTexts.isEmpty) {
      return sanitizeStudyMaterialForPrompt(file.conteudo, maxChars: maxChars);
    }
    final budget =
        (maxChars - 2 * (chapterTexts.length - 1)) ~/ chapterTexts.length;
    if (budget < 40) {
      throw StateError(
          "Selecione menos capítulos por geração para manter trechos legíveis.");
    }
    return chapterTexts
        .map((text) => sanitizeStudyMaterialForPrompt(text, maxChars: budget))
        .where((text) => text.isNotEmpty)
        .join("\n\n");
  }

  LibraryFile generationFile(int maxChars) => LibraryFile(
      id: file.id,
      nome: file.nome,
      categoria: file.categoria,
      conteudo: promptContext(maxChars),
      criadoEm: file.criadoEm);
}

class MaterialScopeStore {
  String _key(LibraryFile file) => AccountScopedPreferences.instance
      .scopedKey('material_chapters:${file.id}');
  Future<String> _fingerprint(String text) async =>
      base64Encode((await Sha256().hash(utf8.encode(text))).bytes);
  Future<List<MaterialChapter>?> load(LibraryFile file) async {
    final account = AccountScopedPreferences.instance.activeAccountId;
    final key = _key(file);
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['fingerprint'] != await _fingerprint(file.conteudo)) {
        throw StateError(
            'O texto do material foi alterado. Revise a seleção de capítulos antes de gerar.');
      }
      if (account != AccountScopedPreferences.instance.activeAccountId) {
        throw StateError('A conta mudou. Selecione o material novamente.');
      }
      final chapters = (json['chapters'] as List)
          .map((c) =>
              MaterialChapter.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList();
      extractSelectedChapters(file.conteudo, chapters);
      return chapters;
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
          'Revise a seleção de capítulos deste material antes de gerar.');
    }
  }

  Future<void> save(LibraryFile file, List<MaterialChapter> chapters) async {
    chapters = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
    extractSelectedChapters(file.conteudo, chapters);
    final account = AccountScopedPreferences.instance.activeAccountId;
    final key = _key(file);
    final fingerprint = await _fingerprint(file.conteudo);
    final preferences = await SharedPreferences.getInstance();
    if (account != AccountScopedPreferences.instance.activeAccountId) {
      throw StateError('A conta mudou. Abra o material novamente.');
    }
    final saved = await preferences.setString(
        key,
        jsonEncode({
          'fingerprint': fingerprint,
          'chapters': chapters.map((c) => c.toJson()).toList()
        }));
    if (!saved) throw StateError('Não foi possível salvar a seleção.');
  }

  Future<void> clear(LibraryFile file) async {
    final key = _key(file);
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Não foi possível restaurar o documento inteiro.');
    }
  }

  Future<ScopedLibraryMaterial> resolve(LibraryFile file) async {
    final chapters = await load(file);
    if (chapters == null) return ScopedLibraryMaterial(file, false);
    return ScopedLibraryMaterial(
        LibraryFile(
            id: file.id,
            nome: file.nome,
            categoria: file.categoria,
            conteudo: extractSelectedChapters(file.conteudo, chapters),
            criadoEm: file.criadoEm),
        true,
        chapterTexts: chapters
            .map((c) => file.conteudo.substring(c.start, c.end))
            .toList());
  }
}

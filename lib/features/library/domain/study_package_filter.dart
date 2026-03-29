import '../../../core/content/study_material_sanitizer.dart';
import 'library_model.dart';

final RegExp _packageTokenPattern = RegExp(r'[a-z0-9]{4,}');

const Set<String> _packageStopwords = {
  'para',
  'com',
  'sem',
  'sobre',
  'entre',
  'pelos',
  'pelas',
  'mais',
  'menos',
  'muito',
  'muita',
  'muitos',
  'muitas',
  'como',
  'quando',
  'onde',
  'qual',
  'quais',
  'porque',
  'uma',
  'umas',
  'uns',
  'esses',
  'essas',
  'esse',
  'essa',
  'este',
  'esta',
  'isto',
  'aquele',
  'aquela',
  'nivel',
  'geral',
  'material',
  'biblioteca',
  'estudo',
  'estudos',
  'conteudo',
  'conteudos',
  'topico',
  'topicos',
  'flashcard',
  'flashcards',
  'questao',
  'questoes',
  'checklist',
  'objetiva',
  'objetivo',
  'resumo',
  'curto',
};

const Set<String> _metadataTokens = {
  'isbn',
  'issn',
  'doi',
  'autor',
  'autores',
  'editora',
  'copyright',
  'ficha',
  'catalografica',
  'catalogacao',
  'sumario',
  'indice',
  'pagina',
  'paginas',
  'referencia',
  'referencias',
  'bibliografia',
  'publicado',
  'revisao',
  'organizacao',
  'traducao',
  'capa',
  'rodape',
  'cabecalho',
  'creditos',
  'link',
  'links',
  'disponivel',
  'acesso',
  'site',
  'sites',
};

const List<String> _metadataMarkers = [
  'isbn',
  'issn',
  'doi',
  'todos os direitos reservados',
  'all rights reserved',
  'copyright',
  'ficha catalog',
  'cataloga',
  'editora',
  'publisher',
  'sumario',
  'indice',
  'table of contents',
  'referencias',
  'referencias bibliograficas',
  'bibliografia',
  'fontes consultadas',
  'publicado por',
  'impresso no brasil',
  'disponivel em',
  'acesso em',
  'http://',
  'https://',
  'www.',
];

StudyPackage sanitizeStudyPackageForMaterial({
  required StudyPackage package,
  required LibraryFile file,
}) {
  final profile = _buildRelevanceProfile(file.nome, file.conteudo);

  final flashcards = package.flashcards
      .where(
        (card) => _isRelevantText(
          '${card['front'] ?? ''}\n${card['back'] ?? ''}',
          profile,
        ),
      )
      .take(16)
      .map(
        (card) => <String, String>{
          'front': (card['front'] ?? '').trim(),
          'back': (card['back'] ?? '').trim(),
        },
      )
      .where((card) => card['front']!.isNotEmpty && card['back']!.isNotEmpty)
      .toList();

  final questoes = package.questoes
      .where((question) {
        final options = question['opcoes'];
        final optionText = options is List
            ? options.take(6).map((item) => '$item').join('\n')
            : '';
        final combined = [
          '${question['pergunta'] ?? ''}',
          '${question['subtema'] ?? ''}',
          '${question['explicacao'] ?? ''}',
          optionText,
        ].join('\n');
        return _isRelevantText(combined, profile);
      })
      .take(10)
      .toList();

  final topicosPrincipais = package.topicosPrincipais
      .where((topic) => _isRelevantText(topic, profile))
      .take(8)
      .toList();

  final checklistEstudo = package.checklistEstudo
      .where(
        (item) => item.trim().isNotEmpty && !_containsMetadataNoise(item),
      )
      .take(10)
      .toList();

  final titleCandidate =
      package.titulo.trim().isEmpty ? file.nome : package.titulo;
  final title = profile.strict &&
          !_isRelevantText('$titleCandidate\n${package.resumoCurto}', profile)
      ? file.nome
      : titleCandidate;

  return StudyPackage(
    titulo: title,
    resumoCurto: package.resumoCurto,
    topicosPrincipais: topicosPrincipais,
    flashcards: flashcards,
    questoes: questoes,
    checklistEstudo: checklistEstudo,
  );
}

class _RelevanceProfile {
  const _RelevanceProfile({
    required this.strict,
    required this.topicTerms,
    required this.anchorTerms,
  });

  final bool strict;
  final Set<String> topicTerms;
  final Set<String> anchorTerms;
}

_RelevanceProfile _buildRelevanceProfile(String topic, String rawContext) {
  final cleanedContext =
      sanitizeStudyMaterialForPrompt(rawContext, maxChars: 6000);
  final topicTerms = _tokenizeRelevance(topic);

  final contextCounts = <String, int>{};
  for (final token in _tokenizeRelevance(cleanedContext)) {
    contextCounts.update(token, (value) => value + 1, ifAbsent: () => 1);
  }

  final sortedContextTerms = contextCounts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return b.key.length.compareTo(a.key.length);
    });

  final anchors = <String>{...topicTerms};
  for (final entry in sortedContextTerms) {
    anchors.add(entry.key);
    if (anchors.length >= 24) break;
  }

  return _RelevanceProfile(
    strict: cleanedContext.length >= 180 && contextCounts.length >= 6,
    topicTerms: topicTerms,
    anchorTerms: anchors,
  );
}

bool _isRelevantText(String text, _RelevanceProfile profile) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (_containsMetadataNoise(trimmed)) return false;
  if (!profile.strict) return true;

  final tokens = _tokenizeRelevance(trimmed);
  if (tokens.isEmpty) return false;

  final topicOverlap = tokens.intersection(profile.topicTerms);
  if (topicOverlap.isNotEmpty) return true;

  final anchorOverlap = tokens.intersection(profile.anchorTerms);
  if (anchorOverlap.length >= 2) return true;

  return anchorOverlap.length == 1 && trimmed.length <= 90;
}

bool _containsMetadataNoise(String text) {
  final normalized = _normalizeMatchText(text);
  if (normalized.isEmpty) return false;
  if (_metadataMarkers.any(normalized.contains)) return true;
  return _tokenizeRelevance(normalized).any(_metadataTokens.contains);
}

Set<String> _tokenizeRelevance(String text) {
  final normalized = _normalizeMatchText(text);
  final tokens = _packageTokenPattern
      .allMatches(normalized)
      .map((match) => match.group(0)!)
      .where(
        (token) =>
            !_packageStopwords.contains(token) &&
            !_metadataTokens.contains(token) &&
            int.tryParse(token) == null,
      )
      .toSet();
  return tokens;
}

String _normalizeMatchText(String input) {
  var text = input.toLowerCase();

  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
    'Ã¡': 'a',
    'Ã ': 'a',
    'Ã¢': 'a',
    'Ã£': 'a',
    'Ã¤': 'a',
    'Ã©': 'e',
    'Ã¨': 'e',
    'Ãª': 'e',
    'Ã«': 'e',
    'Ã­': 'i',
    'Ã¬': 'i',
    'Ã®': 'i',
    'Ã¯': 'i',
    'Ã³': 'o',
    'Ã²': 'o',
    'Ã´': 'o',
    'Ãµ': 'o',
    'Ã¶': 'o',
    'Ãº': 'u',
    'Ã¹': 'u',
    'Ã»': 'u',
    'Ã¼': 'u',
    'Ã§': 'c',
    'Ã±': 'n',
  };

  replacements.forEach((from, to) {
    text = text.replaceAll(from, to);
  });

  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Arquivo armazenado na biblioteca de estudos do usuário.
class LibraryFile {
  final int id;

  /// Processed server PDFs are stored under a negative local ID.
  /// Positive IDs identify local-only imports and must not be sent to the server.
  int? get remoteDocumentId => id < 0 ? -id : null;

  final String nome;
  final String? categoria;
  final String conteudo;
  final DateTime criadoEm;

  const LibraryFile({
    required this.id,
    required this.nome,
    this.categoria,
    required this.conteudo,
    required this.criadoEm,
  });

  /// Converte JSON para [LibraryFile].
  factory LibraryFile.fromJson(Map<String, dynamic> j) => LibraryFile(
        id: j['id'] as int,
        nome: j['nome'] as String,
        categoria: j['categoria'] as String?,
        conteudo: j['conteudo'] as String? ?? '',
        criadoEm: DateTime.parse(j['criado_em'] as String),
      );

  /// Converte [LibraryFile] para JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'categoria': categoria,
        'conteudo': conteudo,
        'criado_em': criadoEm.toIso8601String(),
      };
}

/// Pacote de estudo gerado automaticamente a partir de um arquivo.
/// Contém: resumo, tópicos, questões sugeridas e checklist.
class StudyPackage {
  final String titulo;
  final String resumoCurto;
  final List<String> topicosPrincipais;
  final List<Map<String, dynamic>> questoes; // lista de quiz questions
  final List<String> checklistEstudo;

  StudyPackage({
    required this.titulo,
    required this.resumoCurto,
    required this.topicosPrincipais,
    required this.questoes,
    required this.checklistEstudo,
  });

  /// Converte JSON para [StudyPackage].
  factory StudyPackage.fromJson(Map<String, dynamic> j) => StudyPackage(
        titulo: j['titulo'] as String? ?? 'Pacote de Estudo',
        resumoCurto:
            j['resumo_curto'] as String? ?? j['resumo'] as String? ?? '',
        topicosPrincipais: List<String>.from(
          j['topicos_principais'] ?? j['pontos_chave'] ?? [],
        ),
        questoes: List<Map<String, dynamic>>.from(
          (j['sugestoes_questoes'] ?? j['questoes_revisao'])
                  as List<dynamic>? ??
              [],
        ),
        checklistEstudo: List<String>.from(
          j['checklist_de_estudo'] ?? j['dicas_estudo'] ?? [],
        ),
      );

  /// Converte [StudyPackage] para JSON.
  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'resumo_curto': resumoCurto,
        'topicos_principais': topicosPrincipais,
        'sugestoes_questoes': questoes,
        'checklist_de_estudo': checklistEstudo,
      };
}

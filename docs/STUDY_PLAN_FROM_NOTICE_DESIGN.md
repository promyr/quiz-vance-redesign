# Central de Editais e importação confiável de PDF

## Entendimento aprovado

- O aplicativo deve aceitar somente PDF nos fluxos de edital e biblioteca.
- O usuário envia o edital primeiro; cargo e data não são digitados previamente.
- O sistema extrai cargos e datas do próprio edital e pede ao usuário apenas para
  selecionar o cargo encontrado.
- O processamento não pode depender de uma única requisição longa nem de um corte
  cego nos primeiros caracteres do documento.
- A análise deve continuar em segundo plano e sobreviver a fechamento do app,
  reinício do backend e nova tentativa.
- O PDF original fica em uma Central de Editais privada do usuário até ele excluir.
- A Biblioteca reutiliza o mesmo núcleo de upload, validação e extração.
- O modelo de IA recebe somente trechos relevantes e nunca o arquivo inteiro.
- O resultado precisa indicar páginas de origem para permitir revisão humana.

## Requisitos não funcionais

- Limite operacional: 100 MiB e 2.000 páginas por PDF, configuráveis no backend.
- Upload por fluxo de bytes, sem depender de caminho local Android.
- Validação de assinatura `%PDF-`, arquivo criptografado, quantidade de páginas e
  propriedade do documento em toda rota.
- Estado persistente no PostgreSQL, com tentativas idempotentes e retomada após
  falha transitória.
- Extração página a página; OCR somente em página sem texto utilizável.
- Logs estruturados por `document_id`, `job_id`, etapa, duração e código de erro,
  sem registrar texto do edital nem segredos.
- Contratos versionados e compatibilidade temporária com o endpoint legado.

## Arquitetura aprovada

1. O Flutter seleciona o PDF com `readStream`, valida extensão/tamanho e envia por
   multipart para `POST /v2/documents`.
2. O backend grava o PDF privado e cria um job durável de extração.
3. Um worker com lease no banco processa páginas individualmente, aplicando OCR
   apenas quando a extração nativa não produz texto suficiente.
4. O texto por página é persistido com número, método de extração e qualidade.
5. O pipeline indexa cargos, datas e seções e muda o documento para
   `awaiting_selection`.
6. O Flutter mostra os cargos encontrados; a escolha cria um job de análise do
   conteúdo programático daquele cargo.
7. O backend classifica trechos candidatos, divide a análise em lotes com
   sobreposição, chama o gateway de IA e consolida disciplinas/tópicos com
   evidências de página.
8. O resultado final pode alimentar o gerador de plano existente ou, no propósito
   `library`, fornecer o texto integral extraído para salvar como material.
9. O app lista os documentos na Central de Editais, acompanha progresso por
   polling resiliente, permite retomar, revisar e excluir.

## Estados

`uploading -> extracting -> mapping -> awaiting_selection -> analyzing ->
consolidating -> ready`

Estados de exceção: `needs_review`, `failed`, `deleted`.

Cada job também mantém `queued`, `running`, `retrying`, `completed` ou `failed`,
progresso, tentativa, lease, etapa e erro sanitizado.

## Modelo de dados

- `study_documents`: proprietário, finalidade, nome, hash, bytes privados, tamanho,
  páginas, estado, progresso, metadados extraídos e timestamps.
- `study_document_pages`: documento, página, texto, método (`native`/`ocr`),
  qualidade e hash.
- `study_document_jobs`: documento, tipo, estado, tentativa, lease, payload,
  resultado, erro sanitizado e timestamps.
- Índices por proprietário/estado/data, documento/página e fila/lease.
- Exclusão em cascata remove PDF, páginas e jobs.

## Segurança e privacidade

- Todas as rotas exigem o token do usuário e verificam propriedade.
- O nome original é sanitizado; o MIME declarado não é considerado prova.
- PDFs com JavaScript/anexos não são executados; ferramentas externas rodam com
  timeout e diretório temporário isolado.
- O texto é tratado como dado não confiável e isolado de instruções do sistema.
- O gateway de IA mantém rotação de chaves e retry apenas para erros transitórios.
- A exclusão é explícita e auditável.

## Compatibilidade e rollout

- O endpoint legado `/study-plan/analyze-notice` permanece durante uma versão,
  mas a tela nova usa somente `/v2/documents`.
- A migração é aditiva e possui `downgrade`.
- O worker usa lease para impedir processamento duplicado.
- O rollout exige testes unitários, integração de upload/job/seleção/exclusão,
  PDFs reais digitais e escaneados, análise Flutter, build assinado e smoke em
  produção antes da publicação no tópico Atualizações.

## Decisões

| Decisão | Alternativas consideradas | Motivo |
|---|---|---|
| Central dedicada com núcleo compartilhado | Manter extração isolada em cada tela | Preserva o histórico do edital e elimina duplicação no PDF. |
| Processamento durável assíncrono | Uma requisição longa | Sobrevive a timeout, fechamento do app e reinício. |
| Upload do PDF ao backend | Somente extração no aparelho | Dá comportamento consistente entre Android e desktop e habilita OCR. |
| Texto estruturado por página | String única truncada | Mantém conteúdo do cargo e evidência rastreável. |
| Seleção após descoberta | Cargo/data digitados antes | Segue o edital como fonte de verdade e reduz erro de digitação. |
| OCR seletivo | OCR do documento inteiro | Reduz custo e tempo sem abandonar PDFs escaneados. |
| Armazenamento privado no banco atrás de abstração | Filesystem efêmero | Funciona no Fly sem perda em deploy e permite migrar para objeto privado depois. |
| Compatibilidade temporária | Remoção imediata do endpoint legado | Reduz risco de regressão durante a atualização do APK. |

## Critérios de aceite

- Um edital cujo conteúdo programático está depois do caractere 350.000 encontra o
  cargo e as disciplinas corretas.
- Um PDF escaneado entra em OCR seletivo e não falha por “sem texto” imediatamente.
- Upload Android por `content://` funciona sem caminho de arquivo.
- Interromper e retomar o app não perde o job.
- Falha transitória de provedor é tentada novamente sem duplicar o documento.
- O usuário não consegue ler ou excluir documento de outra conta.
- A Biblioteca importa o resultado do mesmo pipeline.
- Nenhum texto sensível aparece nos logs.

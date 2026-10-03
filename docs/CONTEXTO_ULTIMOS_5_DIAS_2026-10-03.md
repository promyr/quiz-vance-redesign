# Contexto recuperado — 29/09 a 03/10/2026

Período: cinco dias de calendário, inclusive, no horário de São Paulo.
Fontes: commits locais, arquivos atuais e o transcript indicado pelo usuário em
`C:/Users/Belchior/.gemini/antigravity/brain/c9984467-99d0-488e-bb3a-d934896b1756/.system_generated/logs/transcript.jsonl`.
Este documento não copia credenciais ou logs brutos. Descreve mudanças registradas; não equivale a uma nova auditoria integral ou a um teste em aparelho.

## Estado recebido em 03/10

- Branch `main`, HEAD `c9d08dc`, versão pública 2.1.1, build Android 73.
- Recibo da última publicação: APK Telegram 923, changelog 924, tópico Atualizações 6, Gerent3Bot.
- APK 2.1.1: SHA256 BEF48A4D08165B4D88F5D71395021BB6D8A486C5F9686CEF2830146045E3E923.

## Alterações recuperadas

### 29–30/09: integração, estatísticas, revisão e entregas 2.0.67–2.0.71

- Administração central de chaves e uso das chaves mestras pelos usuários; correções anteriores de autenticação e armazenamento integradas aos APKs.
- Revisão explícita de editais em `needs_review`, incluindo cargo informado manualmente e retomada de processamento.
- Estatísticas: submissão de respostas independente de tarefas locais, preservação de respostas ao sair e proteção contra falhas no cache local.
- Plano de Estudos concentrado na Biblioteca; ajustes de navegação e remoção de entradas genéricas duplicadas.
- Home e justificativas de respostas: ajustes para telas estreitas, fontes maiores, botões e badges; geração de testes da Home completa.
- Backend: considerar conteúdo programático distante do quadro de vagas, continuar a análise dos anexos, tentar novamente após erros temporários e invalidar checkpoints antigos.
- Distribuição: manifesto alinhado ao APK realmente servido, atualização pública, assinatura/hash e recibos de entrega pelo bot para impedir duplicação.

### 02/10: edital, variabilidade e versão 2.1.0

- Cargo manual aceito mesmo quando outros cargos já foram parcialmente reconhecidos.
- Mais marcadores de conteúdo programático, conhecimentos básicos/complementares, objetos de conhecimento, anexos e programa das provas.
- Prompt de análise de matérias comuns e limite de saída do worker aumentado para 4.096 tokens.
- Cards de streak/cotas empilhados em telas pequenas; substituição de símbolos por ícones e espaçamento de justificativas.
- Deduplicação de quizzes/simulados: salvar o campo normalizado `text`, com compatibilidade para `pergunta`; fornecer questões anteriores à lista de exclusão da IA.
- Cache protegido para não retornar questões incompletas sem opções, gabarito ou explicação.
- Prompt com variedade de subtemas e tipos cognitivos; rotação temporal de trechos de PDFs longos.
- Contingência para modelos Groq indisponíveis e ajustes dos testes de saúde/modularidade.
- Versão pública passou a usar `x.y.z`; número de build continua separado para o Android.
- Rodízio de chaves por último sucesso, intercalando provedores em geração geral; Gemini prioritário para análise de planos e Groq como contingência.
- Catálogo/configuração de modelos atualizado. Disponibilidade real e afirmações comerciais sobre modelos não foram verificadas nesta recuperação de contexto.

### 03/10: segurança, administração e versão 2.1.1

- Segredos `enc:v2:` com salt aleatório por payload e leitura/migração dos envelopes `enc:v1:` históricos; rejeição de envelopes inválidos.
- Guardas de estado ao selecionar cargo; classificação de quota, autenticação, tamanho, indisponibilidade e timeout dos provedores.
- SQLite dos testes com caminho absoluto; testes de contrato de documentos e bateria adversarial adicionados.
- Autodetecção de provedores pelos prefixos das chaves e reconhecimento local de `AQ.`/`AQ.Ab` no painel.
- Biometria administrativa: janela de validade de 15 segundos e rollback na falha de confirmação.
- Card do Plano de Estudos no topo da Biblioteca.
- Revisão de edital com contagem de disciplinas/tópicos e ações de marcar/desmarcar todas.
- Conclusão de sessões por identificador, atualização visual imediata e recálculo do progresso.
- APK 2.1.1 build 73 assinado e recibo de publicação registrado.

## Planejado, não implementado

`docs/ROADMAP_SMART_CACHE_POOL.md`: pool de questões completas priorizando outros usuários; reutilização para o criador após 100 questões diferentes no mesmo tópico ou esgotamento das inéditas quando a geração não estiver disponível. Não implementar sem pedido explícito. As estimativas de economia/latência no roadmap não representam medições.

## Ressalvas operacionais do histórico

- O commit `88e67fb` também incluiu mudanças em `backend_url.txt`, `BUILD_APK.ps1` e no CI, fora do escopo de segurança original.
- O CI passou a focar o APK universal; o histórico relata retirada do build Windows e da criação automática de GitHub Releases.
- Há relato de restauração de APKs que o usuário havia excluído. Preservar arquivos atuais; não restaurar/remover novamente por inferência.
- Publicações diretas em `main` contornaram requisitos de PR/verificações. Não interpretar a existência de commits como prova de aprovação de todos os checks.
- A versão 2.1.0 foi republicada com binários diferentes no histórico. Próximos APKs devem receber versão/build novos.
- Entrega solicitada pelo usuário: bot no tópico Atualizações, sem substituir por envio manual pelo navegador.

## Correção iniciada nesta tarefa

Ao escolher um item do plano, usar a matéria, todos os tópicos, dificuldade e referência da sessão para gerar e abrir o quiz automaticamente. Não abrir a configuração genérica nem redirecionar à Home por não existir um lote inicial. Registrar início/conclusão exclusivamente no plano e sessão selecionados, e manter tentativa novamente no mesmo fluxo.

## Commits do período

- c9d08dc | 2026-10-03T18:04:52-03:00 | chore: record verified Telegram publication for Android 2.1.1
- 94c9f15 | 2026-10-03T17:44:37-03:00 | release: request Telegram publication for Android 2.1.1
- faccfb1 | 2026-10-03T17:42:03-03:00 | chore(release): update Android 2.1.1 release artifacts and manifest
- adc8c61 | 2026-10-03T17:33:51-03:00 | feat(settings): support new Gemini AQ. and AQ.Ab authentication key prefix in admin panel
- f5b8560 | 2026-10-03T17:17:10-03:00 | feat(study-plan): add discipline and topic stats with select and deselect all actions in edital review
- 9fae3e4 | 2026-10-03T17:13:42-03:00 | fix(study-plan,admin): fix study session completion toggle, biometric enrollment, and master key provider auto-detection
- 88e67fb | 2026-10-03T15:44:26-03:00 | fix(security): implement enc:v2 envelope, robust status guards, and explosive adversarial battery
- 81f151b | 2026-10-03T12:41:51-03:00 | chore(release): update Android 2.1.0 release artifacts and record verified Telegram publication
- 4b55c10 | 2026-10-02T23:36:48-03:00 | feat(ai): update supported models to latest cost-effective generation (Gemini 3.8 Flash and Groq Llama 3.3/3.1)
- f25e5b3 | 2026-10-02T23:31:12-03:00 | feat(ai): least-recently-used key rotation, cross-provider interleaving, and Gemini study plan priority
- ba5c1f4 | 2026-10-02T20:02:34-03:00 | chore: record verified Telegram publication for Android 2.1.0
- 8b99f67 | 2026-10-02T15:39:06-03:00 | release: request Telegram publication for Android 2.1.0
- b79ca8f | 2026-10-02T15:00:17-03:00 | merge: integrate origin/main with v2.1.0 release branch
- c1d19d7 | 2026-10-02T14:57:34-03:00 | release: v2.1.0 - quiz dynamic variability, safe cache, pdf rotation and official release bundle
- 6ba26a2 | 2026-10-02T10:05:54-03:00 | chore: record verified Telegram publication for Android 2.0.72
- 24d852e | 2026-10-02T09:57:56-03:00 | release: publish Android 2.0.72 with manual cargo selection, expanded syllabus markers, and responsive home layout
- db44a92 | 2026-09-30T21:29:41-03:00 | chore: record verified Telegram publication for Android 2.0.71
- 18e2b0e | 2026-09-30T21:24:39-03:00 | release: publish Android 2.0.71 with responsive home and document fixes
- 8aa891b | 2026-09-30T21:20:09-03:00 | fix: include syllabus annexes and retry transient document failures
- d34ddb1 | 2026-09-30T19:20:48-03:00 | fix: record verified Telegram APK delivery and prevent resend
- ef6b197 | 2026-09-30T18:54:35-03:00 | fix: publish requested Android release through Telegram bot
- f5b7b7b | 2026-09-30T18:35:43-03:00 | release: publish Android 2.0.70 with all fixes
- c49334d | 2026-09-30T18:01:15-03:00 | release: publish Android 2.0.69 statistics fixes
- 198a300 | 2026-09-30T17:36:53-03:00 | fix: align update metadata with published APK
- faf5b43 | 2026-09-30T17:31:42-03:00 | fix: add notice review and publish Android 2.0.68
- 0a55c29 | 2026-09-29T04:56:13-03:00 | release: publish Android 2.0.67

## Validação desta correção

Testes de navegação cobrem os botões reais de ambas as telas, seleção do segundo item, geração inicial, falha seguida de retry, todos os tópicos enviados e conclusão no identificador correto. Quizzes avulsos não alteram o plano.
O teste estrutural de arquitetura já falha no tamanho da `library_screen.dart` (1.115 linhas, limite de 1.000); a Biblioteca não foi modificada nesta tarefa. Isso não foi tratado como teste funcional aprovado nem motivo para refatorar arquivos fora do escopo.
Foi encontrado também o fallback do `AppConfig` ainda em 2.1.0; alinhado a 2.1.2. A versão do APK de produção é definida explicitamente pelo script de build.

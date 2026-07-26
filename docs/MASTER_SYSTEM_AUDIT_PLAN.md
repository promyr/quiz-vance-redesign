# Plano Mestre de Auditoria 360° — Quiz Vance

**Versão do plano:** 1.1
**Baseline inicial:** app 2.0.35+34, backend Fly, PostgreSQL, Telegram
**Estratégia escolhida:** auditoria total por gates e evidências
**Regra central:** nenhum item é considerado aprovado sem prova reproduzível.

## 1. Objetivo

Auditar integralmente o Quiz Vance, da experiência no celular até os serviços
externos, banco, infraestrutura e processo de publicação. O plano existe para
impedir desvios de escopo, validações superficiais, reaparecimento de bugs e
declarações de conclusão sem evidência.

O trabalho termina somente quando:

1. todos os componentes estão inventariados;
2. todos os requisitos estão ligados a testes;
3. todos os testes obrigatórios têm evidência;
4. achados P0/P1 estão corrigidos e retestados;
5. riscos residuais estão documentados e aceitos;
6. o release passa no celular real, não apenas no ambiente de desenvolvimento.

## 2. Entendimento confirmado

- Escopo de produção confirmado: Flutter/Android, FastAPI, PostgreSQL, Fly,
  provedores de IA, autenticação, administração, Mercado Pago, Telegram,
  e-mail e integrações realmente habilitadas.
- Windows permanece no inventário porque o CI o compila, mas não pode ser
  chamado de produto suportado até haver decisão formal. iOS, Asaas e SMS
  também ficam como `não confirmado`, nunca como cobertura implícita.
- Usuários: conta gratuita, Premium, administrador e usuário não autenticado.
- Ambientes: desenvolvimento, testes e produção.
- Segurança: nenhuma senha, token ou chave completa pode aparecer em código,
  logs, respostas, screenshots ou relatórios.
- Produção pode receber testes seguros e reversíveis.
- Não serão feitas cobranças reais, exclusões destrutivas, disparos em massa ou
  testes de carga agressivos sem nova autorização.
- Toda publicação é bloqueada por falha crítica, regressão, assinatura inválida,
  migração incompleta, APK divergente ou download não retomável.

## 3. Decisões e alternativas

| Decisão | Alternativas | Motivo |
|---|---|---|
| Auditoria total por gates | Auditoria rápida por risco; ciclos semanais isolados | É a única opção compatível com “não deixar nada passar”. |
| Evidência obrigatória por requisito | Checklist subjetivo | Evita aprovar algo apenas porque “parece funcionar”. |
| Backend como autoridade para admin, quotas e fallback | Regras duplicadas no cliente | Impede divergência entre APKs e servidor. |
| Um APK universal oficial | Vários APKs enviados ao Telegram | Evita versão errada, confusão por tamanho e falha em 99%. |
| Link estável no backend | Binário anexado ao Telegram | Permite retomada HTTP, hash verificável e troca atômica. |
| Correção e reteste por domínio | Grande lote de correções sem isolamento | Facilita descobrir qual mudança criou uma regressão. |

### 3.1 Decisões de escopo ainda obrigatórias

| Item | Estado inicial | Regra de auditoria |
|---|---|---|
| Android | Produto de produção | Cobertura integral e bloqueante |
| Windows | Build existente no CI | Inventariar; suporte depende de decisão explícita |
| iOS | Não confirmado | Não declarar suporte nem cobertura até decisão |
| Mercado Pago | Integração implementada | Cobertura integral e bloqueante |
| Asaas | Citado no mapa, não confirmado na implementação | Corrigir o mapa ou implementar e auditar |
| E-mail | Recuperação implementada | Cobertura integral e entrega controlada |
| SMS | Citado no escopo antigo, não confirmado | Remover do contrato ou implementar e auditar |
| APK universal | Canal oficial do Telegram | É o único artefato oficial; builds split do CI não podem ser publicados nesse canal |

Uma divergência entre mapa, CI, documentação e implementação é um achado, não
uma licença para escolher silenciosamente uma das versões.

## 4. Governança contra desvio

### 4.1 Registro único de controle

Cada item deve entrar na matriz com:

| Campo | Obrigatório |
|---|---|
| ID estável | Sim, exemplo `AUTH-014` |
| Domínio e requisito | Sim |
| Risco associado | Sim |
| Ambiente e perfil usados | Sim |
| Teste automatizado/manual | Sim |
| Comando ou roteiro exato | Sim |
| Resultado esperado e obtido | Sim |
| Evidência | Log, hash, JSON sanitizado, screenshot ou vídeo |
| Status | Não iniciado, executando, falhou, corrigido, aprovado |
| Severidade | P0, P1, P2 ou P3 |
| Arquivo/endpoint responsável | Sim |
| Responsável e revisor | Sim |
| Data, versão e commit | Sim |

### 4.2 Regras imutáveis

- Não usar “feito” sem evidência.
- Não mudar o escopo silenciosamente.
- Não remover teste para fazer a suíte passar.
- Não classificar erro reproduzível como “problema do celular” sem diagnóstico.
- Não publicar artefato que não tenha sido baixado novamente do link público.
- Não misturar correção funcional, redesign e refatoração sem testes separados.
- Toda falha reaberta ganha teste de regressão permanente.
- Toda exceção exige causa, impacto, responsável e prazo.

### 4.3 Matriz executável e fechamento automático

A fonte de controle será `audit/AUDIT_CONTROL_MATRIX.json`; relatórios CSV/HTML
são apenas visões geradas. Cada checkbox deste documento possui um ID estável no
formato `AUDIT-SS-NNN`, em que `SS` é a seção e `NNN` é a ordem congelada do
requisito. IDs nunca são reutilizados: item removido passa a `retired`, com
justificativa.

O validador da matriz deve falhar quando houver:

- ID ausente, duplicado ou desconhecido;
- requisito sem dono, risco, teste, resultado esperado ou evidência;
- componente inventariado sem requisito associado;
- requisito sem componente ou sem classificação;
- evidência apontando para commit, versão ou ambiente diferente;
- status `aprovado` sem revisor independente;
- `unclassified_count`, `untested_count` ou `missing_evidence_count` maior que zero.

O inventário é gerado mecanicamente a partir de:

- rotas Flutter/GoRouter, diretórios de features, providers e armazenamentos;
- OpenAPI e decoradores FastAPI;
- modelos SQLAlchemy, migrations Alembic, constraints e índices;
- jobs, schedulers, scripts, comandos/callbacks/webhooks Telegram;
- variáveis e nomes de secrets, sem ler nem registrar seus valores;
- workflows, Dockerfile, manifests Android, dependências e artefatos.

O Gate 2 só abre com relatório de reconciliação contendo
`unclassified_count == 0`. O inventário inicial deve explicar, no mínimo, a
diferença já observada entre 17 diretórios de features, 68 decoradores de rotas,
19 modelos SQLAlchemy e o mapa de arquitetura que enumera somente 6 features.

## 5. Severidade e prazo

| Nível | Definição | Gate |
|---|---|---|
| P0 | Exposição de segredo/dado, perda de dados, cobrança indevida, takeover, app não abre ou geração indisponível para todos | Bloqueio imediato; contenção antes de continuar |
| P1 | Login/admin quebrado, quota incorreta, APK inválido, download incompleto, fluxo principal sem saída | Bloqueia release |
| P2 | Falha parcial com alternativa, acessibilidade grave, degradação relevante, inconsistência de dados recuperável | Corrigir no ciclo ou aceitar formalmente |
| P3 | Dívida, texto, acabamento ou otimização sem impacto crítico | Backlog rastreado |

## 6. Gates de execução

### Gate 0 — Segurança imediata

- Procurar segredos em todo o histórico, workspace, APK e artefatos.
- Rotacionar credenciais expostas e invalidar versões antigas.
- Confirmar que nenhuma conta usa senha padrão ou bypass local.
- Bloquear scripts que contenham tokens.
- Registrar incidente, alcance e prova da rotação.

**Bloqueador já identificado:** existe token do Telegram gravado em um script
legado do workspace. Ele deve ser rotacionado e removido antes de considerar a
auditoria de segurança aprovada. O valor não deve ser reproduzido no relatório.

### Gate 1 — Inventário e proveniência

- Mapear todos os arquivos, módulos, endpoints, tabelas, migrations, jobs,
  secrets por nome, serviços externos e artefatos.
- Separar código atual de protótipos, backups, APKs e backends antigos.
- Confirmar qual diretório é fonte canônica.
- Identificar arquivos staged, não rastreados e alterações do usuário.
- Gerar mapa requisito → módulo → endpoint → tabela → teste.
- Gerar a matriz versionada com IDs e validar contadores iguais a zero.
- Congelar um manifesto de proveniência com commit, estado da árvore, versões
  de toolchain, lockfiles, Alembic head, digest da imagem, certificado e hash do
  APK, URL pública, hash baixado e mensagem oficial do Telegram.
- Resolver explicitamente as divergências Flutter 3.24.5/3.41.4,
  Android/Windows/iOS, Mercado Pago/Asaas, e-mail/SMS e universal/split APK.

### Gate 2 — Auditorias por domínio

Executar as seções 7 a 27. Cada domínio precisa de dois estados independentes:
`implementação revisada` e `comportamento comprovado`.

### Gate 3 — Correção controlada

- Criar teste que falha ou reprodução determinística.
- Corrigir a causa raiz.
- Rodar lint e testes focados.
- Rodar regressão do domínio afetado.
- Revisar segurança e contratos após a correção.

### Gate 4 — Regressão total

- Flutter analyze.
- Toda a suíte Flutter.
- Testes, lint, compilação e segurança do backend.
- Migrações e contratos.
- E2E dos fluxos principais.
- Matriz de dispositivos e conectividade.

### Gate 5 — Release e produção

- Build universal somente do flavor `production`.
- Versão, package ID, assinatura, tamanho e SHA-256.
- Deploy com migration e rollback definido.
- Download público completo e por faixa.
- Telegram apontando para o mesmo hash.
- Instalação, abertura, login e geração em celular real.
- Contratos e schema compatíveis com APK N, N−1 e N−2.
- Rollback ensaiado com o schema já migrado.

## 7. Repositório, arquitetura e dívida técnica

- [ ] **[AUDIT-07-001]** Fonte canônica única para Flutter e backend.
- [ ] **[AUDIT-07-002]** Ausência de cópias divergentes de regras de negócio.
- [ ] **[AUDIT-07-003]** Limpeza controlada de protótipos, APKs antigos e diretórios de auditoria.
- [ ] **[AUDIT-07-004]** Camadas UI/aplicação/dados/infra sem dependências invertidas.
- [ ] **[AUDIT-07-005]** Componentes com responsabilidade única e nomes coerentes.
- [ ] **[AUDIT-07-006]** Ausência de código morto, TODO crítico e catches silenciosos.
- [ ] **[AUDIT-07-007]** Erros tipados e mensagens de usuário separadas de detalhes internos.
- [ ] **[AUDIT-07-008]** Configuração por ambiente, sem URL ou credencial secreta hardcoded.
- [ ] **[AUDIT-07-009]** Mapas `architecture_map.json/html` iguais à implementação.
- [ ] **[AUDIT-07-010]** README, runbook, rollback e processo de release atualizados.

**Evidências:** grafo de dependências, inventário, lint, busca de duplicação,
lista de código morto e revisão de diffs.

## 8. Inicialização, estado global e navegação Flutter

- [ ] **[AUDIT-08-001]** Inicialização de bindings, armazenamento, banco e observabilidade.
- [ ] **[AUDIT-08-002]** Bootstrap não trava, não pisca tela incorreta e tem timeout.
- [ ] **[AUDIT-08-003]** GoRouter protege rotas autenticadas e administrativas.
- [ ] **[AUDIT-08-004]** Deep links e retorno de aplicações externas preservam estado.
- [ ] **[AUDIT-08-005]** Back button e bottom navigation não duplicam pilhas.
- [ ] **[AUDIT-08-006]** Loading, vazio, erro, offline e retry existem em toda tela assíncrona.
- [ ] **[AUDIT-08-007]** Troca de conta invalida providers e dados do usuário anterior.
- [ ] **[AUDIT-08-008]** Reabertura após kill do Android restaura somente o que foi autorizado.
- [ ] **[AUDIT-08-009]** Rotação, background/foreground e baixa memória não corrompem estado.

## 9. Autenticação, sessão e conta

Matriz obrigatória: cadastro, login, lembrar login ligado/desligado, logout,
refresh, token expirado, offline, 401, 403, 422, 429 e 5xx.

- [ ] **[AUDIT-09-001]** IDs/e-mails normalizados e únicos.
- [ ] **[AUDIT-09-002]** Senha validada e hash forte no backend.
- [ ] **[AUDIT-09-003]** Nenhuma senha fixa ou login local especial.
- [ ] **[AUDIT-09-004]** JWT tem expiração, `auth_version`, refresh e revogação.
- [ ] **[AUDIT-09-005]** Logout e troca de senha invalidam sessões corretamente.
- [ ] **[AUDIT-09-006]** “Lembrar login” persiste sessão apenas quando selecionado.
- [ ] **[AUDIT-09-007]** Falha offline usa cache seguro; 401/403 falha fechado.
- [ ] **[AUDIT-09-008]** Cadastro e login não enumeram contas.
- [ ] **[AUDIT-09-009]** Recuperação de senha por SMS/e-mail tem expiração, uso único,
  rate limit, antifraude e resposta neutra.
- [ ] **[AUDIT-09-010]** Canal real de recuperação está declarado sem ambiguidade; e-mail cobre
  SPF/DKIM/DMARC, bounce, spam, reenvio, invalidação e entrega controlada.
- [ ] **[AUDIT-09-011]** Alteração de login e exclusão de conta exigem reautenticação adequada.
- [ ] **[AUDIT-09-012]** Exclusão remove ou anonimiza dados conforme política.

## 10. Administração e cofre de chaves

- [ ] **[AUDIT-10-001]** `ADMIN_LOGIN_ID` apenas promove conta existente.
- [ ] **[AUDIT-10-002]** Todas as rotas `/admin` exigem JWT e `role=admin`.
- [ ] **[AUDIT-10-003]** Usuário comum recebe 403; token ausente/expirado recebe 401.
- [ ] **[AUDIT-10-004]** O aplicativo nunca recebe chave completa já armazenada.
- [ ] **[AUDIT-10-005]** Segredo é criptografado em repouso e mascarado em respostas.
- [ ] **[AUDIT-10-006]** Campo móvel é obscuro, sem autocorreção/sugestões.
- [ ] **[AUDIT-10-007]** Criar, rotacionar, testar, ativar, priorizar e excluir têm auditoria.
- [ ] **[AUDIT-10-008]** A trilha não registra segredos.
- [ ] **[AUDIT-10-009]** Migração de pool local é idempotente e apaga plaintext só após sucesso.
- [ ] **[AUDIT-10-010]** Teste de chave ocorre no servidor, com timeout e limite.
- [ ] **[AUDIT-10-011]** Reordenação é consistente em falha parcial e concorrência.
- [ ] **[AUDIT-10-012]** Sessões administrativas antigas são revogadas após promoção/alteração.
- [ ] **[AUDIT-10-013]** MFA ou step-up é obrigatório para criar, rotacionar, ativar e excluir chave.
- [ ] **[AUDIT-10-014]** Operação sensível exige reautenticação recente e gera notificação.
- [ ] **[AUDIT-10-015]** Sessões e dispositivos administrativos podem ser revisados e revogados.
- [ ] **[AUDIT-10-016]** Existe recuperação de emergência sem bypass permanente e proteção contra lockout.
- [ ] **[AUDIT-10-017]** A chave que cifra o cofre possui ciclo de rotação e restore ensaiado.

## 11. AI Gateway, provedores e quotas

Matriz: Gemini, OpenAI e Groq × chave pessoal, pool, ambiente, inválida,
expirada, sem crédito, 429, timeout, 5xx, resposta vazia e JSON inválido.

- [ ] **[AUDIT-11-001]** Modelos atuais e compatíveis por provedor.
- [ ] **[AUDIT-11-002]** Modelos descontinuados nunca são reutilizados.
- [ ] **[AUDIT-11-003]** Ordem: preferência pessoal → pool saudável → fallback autorizado.
- [ ] **[AUDIT-11-004]** Circuit breaker persiste por chave e não somente em memória.
- [ ] **[AUDIT-11-005]** 401/403, quota, rate limit, timeout e erro de modelo são classificados.
- [ ] **[AUDIT-11-006]** Falha de uma chave não consome quota do usuário como sucesso.
- [ ] **[AUDIT-11-007]** Uma geração lógica não é cobrada/contada várias vezes por retries.
- [ ] **[AUDIT-11-008]** Idempotência evita conteúdo duplicado em retry de rede.
- [ ] **[AUDIT-11-009]** Limites free/Premium/admin vêm de uma autoridade única.
- [ ] **[AUDIT-11-010]** Data/hora e timezone não resetam quota indevidamente.
- [ ] **[AUDIT-11-011]** Concorrência não ultrapassa quota.
- [ ] **[AUDIT-11-012]** Custos, tokens, latência e taxa de fallback são observáveis.
- [ ] **[AUDIT-11-013]** Prompts não permitem vazamento de segredo ou prompt injection via PDF.
- [ ] **[AUDIT-11-014]** Saídas têm schema, tamanho máximo e sanitização.
- [ ] **[AUDIT-11-015]** Corpus dourado em português mede schema válido, factualidade, resposta
  correta, relevância ao material, duplicação e regressão por modelo.

## 12. Quiz objetivo

- [ ] **[AUDIT-12-001]** Tema manual e material da biblioteca.
- [ ] **[AUDIT-12-002]** Quantidade mínima/máxima e regras free/Premium.
- [ ] **[AUDIT-12-003]** Dificuldades e modo infinito.
- [ ] **[AUDIT-12-004]** Perguntas, opções, índice correto e explicações válidas.
- [ ] **[AUDIT-12-005]** Deduplicação entre sessões.
- [ ] **[AUDIT-12-006]** Cronologia de loading/cancelamento/retry.
- [ ] **[AUDIT-12-007]** Sessão restaura sem perder resposta.
- [ ] **[AUDIT-12-008]** Correção visual e cálculo de resultado.
- [ ] **[AUDIT-12-009]** XP, streak, histórico e quota incrementam uma vez.
- [ ] **[AUDIT-12-010]** Limpeza de memória por tema e global.

## 13. Simulado

- [ ] **[AUDIT-13-001]** Geração por tema/material e quantidade.
- [ ] **[AUDIT-13-002]** Cronômetro em background, pausa e mudança de relógio.
- [ ] **[AUDIT-13-003]** Submissão parcial/total e dupla submissão.
- [ ] **[AUDIT-13-004]** Resultado, revisão de erros e persistência.
- [ ] **[AUDIT-13-005]** Respostas corretas por índice, letra e payload legado.
- [ ] **[AUDIT-13-006]** Acessibilidade do cronômetro e alertas sem depender só de cor.

## 14. Questão aberta e correção

- [ ] **[AUDIT-14-001]** Pergunta autônoma e alinhada ao conteúdo.
- [ ] **[AUDIT-14-002]** Resposta vazia, longa e com caracteres especiais.
- [ ] **[AUDIT-14-003]** Rubrica, nota, feedback e critérios consistentes.
- [ ] **[AUDIT-14-004]** Correção não inventa referência inexistente.
- [ ] **[AUDIT-14-005]** Limite semanal e plano Premium.
- [ ] **[AUDIT-14-006]** Retry não duplica consumo.

## 15. Flashcards e repetição espaçada

- [ ] **[AUDIT-15-001]** Geração manual e por IA.
- [ ] **[AUDIT-15-002]** Persistência local/remota e sincronização.
- [ ] **[AUDIT-15-003]** Algoritmo SRS/FSRS, datas, timezone e virada do dia.
- [ ] **[AUDIT-15-004]** Avaliações repetidas, offline e conflito entre dispositivos.
- [ ] **[AUDIT-15-005]** Deduplicação e exclusão.
- [ ] **[AUDIT-15-006]** Recompensas de gamificação idempotentes.
- [ ] **[AUDIT-15-007]** Acessibilidade de virar cartão e botões de avaliação.

## 16. Biblioteca, PDF e importação

- [ ] **[AUDIT-16-001]** Seleção de PDF e formatos suportados.
- [ ] **[AUDIT-16-002]** Permissão Android e cancelamento do seletor.
- [ ] **[AUDIT-16-003]** MIME, extensão, magic bytes, tamanho e arquivo corrompido.
- [ ] **[AUDIT-16-004]** PDF vazio, protegido, escaneado, gigante e com muitas páginas.
- [ ] **[AUDIT-16-005]** Texto UTF-8, acentos, emoji, tabelas e quebra de linha.
- [ ] **[AUDIT-16-006]** Limites de memória e truncamento explícito.
- [ ] **[AUDIT-16-007]** Extração nunca bloqueia a UI.
- [ ] **[AUDIT-16-008]** Conteúdo malicioso não injeta instruções no prompt.
- [ ] **[AUDIT-16-009]** Pacote de estudo não gera perguntas sobre metadados editoriais.
- [ ] **[AUDIT-16-010]** Prefetch offline, remoção e isolamento por conta.
- [ ] **[AUDIT-16-011]** Arquivo temporário e dados sensíveis são limpos corretamente.

## 17. Plano de estudo, ranking, conquistas e histórico

- [ ] **[AUDIT-17-001]** Plano respeita data, semanas, carga, objetivos e timezone.
- [ ] **[AUDIT-17-002]** Ranking por período, empate, paginação e privacidade.
- [ ] **[AUDIT-17-003]** Conquista desbloqueia uma vez e sincroniza.
- [ ] **[AUDIT-17-004]** XP, nível, streak e maior streak nunca divergem.
- [ ] **[AUDIT-17-005]** Histórico ordena, pagina, filtra e preserva autoria do usuário.
- [ ] **[AUDIT-17-006]** Notebook de erros inclui apenas questões elegíveis.
- [ ] **[AUDIT-17-007]** Operações offline convergem após sincronização.

## 18. Perfil, avatar e preferências

- [ ] **[AUDIT-18-001]** Leitura/edição de nome, login e avatar.
- [ ] **[AUDIT-18-002]** Avatar por URL/data URI, tipo, tamanho e imagem inválida.
- [ ] **[AUDIT-18-003]** Preferências são isoladas por conta.
- [ ] **[AUDIT-18-004]** Chaves pessoais são armazenadas de forma segura.
- [ ] **[AUDIT-18-005]** Troca de provedor sincroniza modelo compatível.
- [ ] **[AUDIT-18-006]** Logout não apaga indevidamente dados que devem permanecer offline.
- [ ] **[AUDIT-18-007]** Exclusão de conta limpa tokens, cache, banco e arquivos locais.

## 19. Billing, Premium e webhooks

- [ ] **[AUDIT-19-001]** Lista de planos e fallback informativo.
- [ ] **[AUDIT-19-002]** Status Premium sempre vem do backend.
- [ ] **[AUDIT-19-003]** Checkout valida usuário, plano, valor e moeda no servidor.
- [ ] **[AUDIT-19-004]** Não confiar em preço enviado pelo cliente.
- [ ] **[AUDIT-19-005]** Webhook valida assinatura/token e é idempotente.
- [ ] **[AUDIT-19-006]** Reenvio, atraso, ordem invertida, chargeback e expiração.
- [ ] **[AUDIT-19-007]** Reconciliação recupera webhook perdido.
- [ ] **[AUDIT-19-008]** Renovação, cancelamento, upgrade/downgrade, grace period, falha,
  reembolso, dunning, disputa e recorrência mensal são reconciliados.
- [ ] **[AUDIT-19-009]** Conta free nunca vira Premium por falha de rede.
- [ ] **[AUDIT-19-010]** Conta Premium não perde acesso por cache transitório.
- [ ] **[AUDIT-19-011]** Logs e analytics não contêm dados de pagamento.
- [ ] **[AUDIT-19-012]** Testes usam sandbox; nenhuma cobrança real.

## 20. API FastAPI e contratos

Todos os endpoints devem entrar em inventário. Para cada um:

- [ ] **[AUDIT-20-001]** Método, path, request, response e códigos documentados.
- [ ] **[AUDIT-20-002]** Auth/RBAC/ownership corretos.
- [ ] **[AUDIT-20-003]** Schemas rejeitam tipo, tamanho e campo inválido.
- [ ] **[AUDIT-20-004]** Limite, paginação, ordenação e filtros.
- [ ] **[AUDIT-20-005]** 400/401/403/404/409/422/426/429/5xx coerentes.
- [ ] **[AUDIT-20-006]** Rate limit por IP/usuário em fluxos caros.
- [ ] **[AUDIT-20-007]** Idempotência em criação, submissão, consumo e webhook.
- [ ] **[AUDIT-20-008]** Nenhuma propriedade sensível em resposta.
- [ ] **[AUDIT-20-009]** CORS, headers e HTTPS.
- [ ] **[AUDIT-20-010]** Rotas legadas não contornam routers novos.
- [ ] **[AUDIT-20-011]** Endpoints internos exigem autenticação forte e não são públicos.
- [ ] **[AUDIT-20-012]** OpenAPI corresponde à implementação.

## 21. PostgreSQL, modelos e migrations

- [ ] **[AUDIT-21-001]** Alembic tem um único head e cadeia contínua.
- [ ] **[AUDIT-21-002]** Upgrade do zero e de uma cópia da versão anterior.
- [ ] **[AUDIT-21-003]** Downgrade quando suportado; rollback alternativo quando não.
- [ ] **[AUDIT-21-004]** Colunas, nullability, defaults, índices e foreign keys.
- [ ] **[AUDIT-21-005]** Unicidade e isolamento por usuário.
- [ ] **[AUDIT-21-006]** Transações e rollback em falha parcial.
- [ ] **[AUDIT-21-007]** Corridas em quota, streak, chave, checkout e webhook.
- [ ] **[AUDIT-21-008]** N+1, consultas lentas e índices ausentes.
- [ ] **[AUDIT-21-009]** Datas UTC no banco e conversão correta no cliente.
- [ ] **[AUDIT-21-010]** Backup restaurável testado, não apenas criado.
- [ ] **[AUDIT-21-011]** Retenção, anonimização e exclusão.
- [ ] **[AUDIT-21-012]** Pool de conexões e comportamento com banco indisponível.

## 22. Armazenamento local, offline e sincronização

- [ ] **[AUDIT-22-001]** SQLCipher realmente cifra o arquivo.
- [ ] **[AUDIT-22-002]** Chave de banco em armazenamento seguro.
- [ ] **[AUDIT-22-003]** Migração preserva dados e tem rollback.
- [ ] **[AUDIT-22-004]** Escopo por conta em tabelas, cache e preferências.
- [ ] **[AUDIT-22-005]** Fila offline é idempotente e ordenada.
- [ ] **[AUDIT-22-006]** Conflitos têm regra explícita.
- [ ] **[AUDIT-22-007]** Backoff, limite de retry e dead-letter.
- [ ] **[AUDIT-22-008]** Falta de espaço, banco corrompido e escrita interrompida.
- [ ] **[AUDIT-22-009]** Nenhum segredo em SharedPreferences ou logs.
- [ ] **[AUDIT-22-010]** Limpeza seletiva em logout e total em exclusão.

## 23. Telegram, SMS, e-mail e notificações

- [ ] **[AUDIT-23-001]** Token apenas em secret; rotação e revogação comprovadas.
- [ ] **[AUDIT-23-002]** Webhook usa secret e valida origem esperada.
- [ ] **[AUDIT-23-003]** Grupo, tópicos, comandos e permissões do bot.
- [ ] **[AUDIT-23-004]** Link fixado aponta para manifesto e APK atuais.
- [ ] **[AUDIT-23-005]** Nenhum APK antigo permanece apresentado como oficial.
- [ ] **[AUDIT-23-006]** Mensagens têm UTF-8 correto e links válidos.
- [ ] **[AUDIT-23-007]** Falha do Telegram não derruba API principal.
- [ ] **[AUDIT-23-008]** SMS/e-mail têm provider, timeout, retry, rate limit e observabilidade.
- [ ] **[AUDIT-23-009]** Reset não revela existência de conta.
- [ ] **[AUDIT-23-010]** Push respeita permissão, opt-out e canal Android.
- [ ] **[AUDIT-23-011]** Nenhum disparo em massa durante a auditoria.

## 24. UI, UX, conteúdo e acessibilidade

Auditar todas as telas em fonte 1,0× e máxima, modo claro/escuro se aplicável,
retrato, teclado aberto e telas pequenas.

- [ ] **[AUDIT-24-001]** Hierarquia, contraste, legibilidade e consistência visual.
- [ ] **[AUDIT-24-002]** Touch targets de pelo menos 48dp.
- [ ] **[AUDIT-24-003]** Semântica, labels e ordem de foco.
- [ ] **[AUDIT-24-004]** TalkBack para navegação e ações principais.
- [ ] **[AUDIT-24-005]** Estado não depende somente de cor/emoji.
- [ ] **[AUDIT-24-006]** Formulários têm label, ajuda, erro e foco no campo.
- [ ] **[AUDIT-24-007]** Teclado não cobre CTA.
- [ ] **[AUDIT-24-008]** Loading informa progresso e permite recuperação.
- [ ] **[AUDIT-24-009]** Textos não cortam nem estouram layout.
- [ ] **[AUDIT-24-010]** Português correto, sem mojibake e sem mensagens internas em inglês.
- [ ] **[AUDIT-24-011]** Datas, moeda, números e plurais localizados.
- [ ] **[AUDIT-24-012]** Animações respeitam redução de movimento.
- [ ] **[AUDIT-24-013]** Fluxos críticos cabem em poucas ações e possuem confirmação adequada.

## 25. Performance, estabilidade e consumo

### 25.1 Baseline NFR bloqueante

Estes são os alvos iniciais bloqueantes. Mudança exige decisão versionada,
justificativa e aprovação; nunca pode ocorrer apenas para fazer um teste passar.
A matriz registra método, ambiente, amostra e orçamento máximo de regressão.

| Indicador | Alvo inicial bloqueante |
|---|---|
| Cold/warm start e primeira interação | aparelho 4 GB: cold p95 ≤ 3,0 s; warm p95 ≤ 1,5 s; interação p95 ≤ 3,5 s |
| Login e refresh | p95 ≤ 800 ms; p99 ≤ 1,5 s; erro servidor < 0,5%, excluindo cold start documentado |
| Geração por provedor e fallback | p95 ≤ 45 s; p99 ≤ 90 s; sucesso lógico ≥ 98,0% |
| Download do APK | conclusão ≥ 99,0%; retomada 206 em 100% dos casos elegíveis; zero divergência de hash |
| Banco/API | 100 sessões e 20 gerações concorrentes sem corrupção; p95 não degrada mais de 20% |
| Qualidade IA | schema válido 100%; resposta correta ≥ 95%; relevância ≥ 95%; duplicação < 2% no corpus dourado |
| Disponibilidade | API 99,9% mensal; geração 99,0%; error budget mensal explícito |
| Estabilidade móvel | crash-free sessions ≥ 99,5%; ANR < 0,47%; frames lentos < 5% nos fluxos críticos |
| Recuperação | RPO ≤ 15 min; RTO ≤ 60 min; restore consistente em 100% dos ensaios |
| Capacidade/custo | custo médio por quiz de 10 questões ≤ US$ 0,05; alerta diário em US$ 20; limites revistos com uso real |

- [ ] **[AUDIT-25-001]** Cold start, warm start e tempo até primeira interação.
- [ ] **[AUDIT-25-002]** Latência p50/p95/p99 de login, geração, sync e download.
- [ ] **[AUDIT-25-003]** Memória em PDF grande, quiz longo e navegação repetida.
- [ ] **[AUDIT-25-004]** Vazamentos de controllers, streams, timers e providers.
- [ ] **[AUDIT-25-005]** Jank e frames perdidos nas telas principais.
- [ ] **[AUDIT-25-006]** Tamanho do APK e assets não usados.
- [ ] **[AUDIT-25-007]** CPU, bateria e rede em background.
- [ ] **[AUDIT-25-008]** Cache com limite e invalidação.
- [ ] **[AUDIT-25-009]** Timeout e cancelamento de requests.
- [ ] **[AUDIT-25-010]** Backend sob concorrência segura, sem teste destrutivo em produção.
- [ ] **[AUDIT-25-011]** Consultas e conexões não crescem sem limite.

## 26. Android, build, assinatura e distribuição

- [ ] **[AUDIT-26-001]** `applicationId`, versionName, versionCode e flavor production.
- [ ] **[AUDIT-26-002]** Min/target/compile SDK e compatibilidade por versão Android.
- [ ] **[AUDIT-26-003]** Permissões mínimas e justificadas.
- [ ] **[AUDIT-26-004]** Network Security Config, backup e extração de dados.
- [ ] **[AUDIT-26-005]** Keystore de produção, cadeia de assinatura e continuidade.
- [ ] **[AUDIT-26-006]** ProGuard/R8 quando habilitado.
- [ ] **[AUDIT-26-007]** APK instala como atualização sobre versão anterior.
- [ ] **[AUDIT-26-008]** Instalação limpa e atualização preservam dados.
- [ ] **[AUDIT-26-009]** APK abre sem pedido de “reparo”.
- [ ] **[AUDIT-26-010]** Arquiteturas ABI necessárias presentes.
- [ ] **[AUDIT-26-011]** Link responde HEAD/GET, tamanho correto e `Accept-Ranges`.
- [ ] **[AUDIT-26-012]** Rota latest e versionada cobrem GET/HEAD e respostas 200/206/416.
- [ ] **[AUDIT-26-013]** ETag/cache, troca atômica e concorrência durante deploy são corretos.
- [ ] **[AUDIT-26-014]** Download completo e retomado termina em 100%.
- [ ] **[AUDIT-26-015]** Hash baixado é igual ao hash construído e ao publicado.
- [ ] **[AUDIT-26-016]** Telegram mostra somente o link oficial atual.
- [ ] **[AUDIT-26-017]** `zipalign`, integridade ZIP, `aapt/apkanalyzer` e certificado são validados.
- [ ] **[AUDIT-26-018]** Exported components, deep-link hijacking, intent spoofing, screenshots,
  clipboard, logs, notificações bloqueadas e cleartext/TLS são auditados.

## 27. Infraestrutura, observabilidade e operação

- [ ] **[AUDIT-27-001]** Dockerfile reproduzível, imagem mínima e usuário não root planejado.
- [ ] **[AUDIT-27-002]** Secrets apenas no Fly e inventário por nome.
- [ ] **[AUDIT-27-003]** Health liveness/readiness separadas e banco verificado.
- [ ] **[AUDIT-27-004]** Auto-start/stop não causa timeout inaceitável.
- [ ] **[AUDIT-27-005]** Região, capacidade, concorrência e timeout adequados.
- [ ] **[AUDIT-27-006]** Logs estruturados com correlation ID e sanitização.
- [ ] **[AUDIT-27-007]** Métricas de erro, latência, geração, quota, fallback e billing.
- [ ] **[AUDIT-27-008]** Alertas com limiar, responsável e runbook.
- [ ] **[AUDIT-27-009]** SLOs propostos: disponibilidade, taxa de geração e latência.
- [ ] **[AUDIT-27-010]** Deploy rolling, migration antes do tráfego e rollback.
- [ ] **[AUDIT-27-011]** Imagem anterior e procedimento de reversão conhecidos.
- [ ] **[AUDIT-27-012]** Recuperação de banco e indisponibilidade de provedor.
- [ ] **[AUDIT-27-013]** Relógio, timezone e certificados monitorados.

### 27.1 CI/CD, supply chain e proveniência

- [ ] **[AUDIT-27-014]** Branch protection e revisão obrigatória estão configuradas.
- [ ] **[AUDIT-27-015]** CI do backend e do Flutter executa gates equivalentes aos locais.
- [ ] **[AUDIT-27-016]** Actions são pinadas, dependências/lockfiles têm integridade e licenças revisadas.
- [ ] **[AUDIT-27-017]** SBOM é gerado para backend e APK; dependências e container são escaneados.
- [ ] **[AUDIT-27-018]** Dockerfile é reproduzível, roda como usuário não-root e não baixa conteúdo mutável.
- [ ] **[AUDIT-27-019]** Keystore, senha e assinatura ficam fora do repositório com acesso mínimo.
- [ ] **[AUDIT-27-020]** Manifesto imutável liga commit → migration → digest da imagem Fly →
  certificado/SHA do APK → URL/hash baixado → mensagem Telegram.
- [ ] **[AUDIT-27-021]** Release não nasce de árvore suja ou toolchain divergente.
- [ ] **[AUDIT-27-022]** Flutter, Java, Gradle, Python e ferramentas Android têm versões únicas no
  mapa, CI, ambiente de release e manifesto.
- [ ] **[AUDIT-27-023]** Backend N continua compatível com APK N−1 e N−2 durante e após migration.
- [ ] **[AUDIT-27-024]** Migrations seguem expand-contract e rollback é testado com schema avançado.

## 28. Segurança e privacidade transversal

- [ ] **[AUDIT-28-001]** Varredura de segredo em workspace, Git, APK e logs.
- [ ] **[AUDIT-28-002]** SAST Dart/Python e análise de dependências.
- [ ] **[AUDIT-28-003]** OWASP API Top 10: BOLA, auth, propriedades, consumo, função, SSRF,
  configuração, inventário e APIs terceiras.
- [ ] **[AUDIT-28-004]** Uploads, URLs, SQL, JSON e headers validados por allowlist.
- [ ] **[AUDIT-28-005]** Criptografia em trânsito e repouso.
- [ ] **[AUDIT-28-006]** Tokens curtos, refresh revogável e rotação de secrets.
- [ ] **[AUDIT-28-007]** Proteção contra brute force e enumeração.
- [ ] **[AUDIT-28-008]** Admin com menor privilégio e auditoria.
- [ ] **[AUDIT-28-009]** PII inventariada, finalidade, retenção e exclusão.
- [ ] **[AUDIT-28-010]** LGPD cobre consentimento para PDF/PII em provedores, menores,
  subprocessadores, residência, exportação e pedidos do titular.
- [ ] **[AUDIT-28-011]** Backups e logs respeitam a mesma política de privacidade.
- [ ] **[AUDIT-28-012]** APK não contém endpoint secreto, senha ou chave de produção.
- [ ] **[AUDIT-28-013]** Respostas e erros não expõem stack, SQL ou configuração.
- [ ] **[AUDIT-28-014]** Plano de incidente para segredo, conta, pagamento e perda de dados.

## 29. Estratégia de testes

### 29.1 Camadas

1. **Estático:** format, analyze, Ruff, Bandit, busca de segredos e encoding.
2. **Unitário:** regras puras, parsing, quotas, datas, modelos e erros.
3. **Componente/widget:** telas, semântica, estados e navegação.
4. **Integração:** Flutter ↔ API, API ↔ banco e serviços simulados.
5. **Contrato:** todos os endpoints e payloads.
6. **E2E:** jornadas completas por perfil.
7. **Resiliência:** offline, timeout, 429, 5xx, processo reiniciado.
8. **Produção segura:** smoke sem cobrança ou destruição.
9. **Dispositivo real:** download, instalação, atualização, abertura e geração.

### 29.2 Matriz mínima

| Dimensão | Valores |
|---|---|
| Perfil | anônimo, free, Premium, admin |
| Sessão | nova, lembrada, expirada, revogada, offline |
| Android | API mínima, intermediária, atual; aparelho fraco e comum |
| Rede | Wi-Fi, móvel, lenta, perda, retomada, offline |
| IA | Gemini, OpenAI, Groq; pessoal, pool, ambiente; erro/quota |
| Origem | tema manual, PDF, biblioteca, cache offline |
| Conta | primeira, troca de conta, exclusão e reinstalação |
| Release | instalação limpa, upgrade, downgrade bloqueado, link Telegram |

### 29.3 Jornadas E2E obrigatórias

1. Novo usuário → cadastro → login lembrado → quiz → resultado → histórico.
2. Login sem lembrar → fechar app → sessão não restaurada.
3. Usuário free → atingir quota → mensagem correta → virada da quota.
4. Premium → geração sem limite free → billing/status consistente.
5. Admin → login normal → adicionar chave → testar → priorizar → auditar.
6. Chave principal 429 → fallback → sucesso → saúde persistida.
7. PDF → importar → gerar pacote → quiz e flashcards relacionados.
8. Offline → estudar dados locais → voltar online → sincronizar uma vez.
9. Checkout sandbox → webhook duplicado → Premium ativado uma vez.
10. Telegram → link → download 100% → instalar → abrir → gerar.
11. Backend novo → APK N−2 → login/geração → migration → rollback compatível.
12. Admin → step-up/MFA → rotacionar chave → notificação → revogar sessão.

## 30. Comandos mínimos de evidência

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --flavor production --target lib/main.dart --no-pub
apksigner verify --verbose --print-certs <apk>
Get-FileHash -Algorithm SHA256 <apk>

python -m pytest backend/tests -q
python -m ruff check backend/app backend/tests
python -m bandit -r backend/app -ll
python -m compileall -q backend/app backend/alembic
alembic heads

node scripts/repair_mojibake.mjs --check
node scripts/assign_audit_ids.mjs
node scripts/build_audit_matrix.mjs
node scripts/inventory_audit_components.mjs
node scripts/validate_audit_matrix.mjs
node scripts/validate_audit_matrix.mjs --strict
```

Comandos de produção devem ser executados sem imprimir valores de secrets.
O modo estrutural deve passar desde a criação do plano. O modo `--strict` deve
falhar até inventário, classificação, execução, evidências e revisão estarem
completos; somente sua aprovação abre o Gate 2.

## 31. Gate de release — bloqueadores absolutos

Não publicar se qualquer condição for verdadeira:

- P0/P1 aberto;
- teste obrigatório falhando;
- lint/analyze falhando;
- migração sem head único ou sem prova no banco real;
- health/readiness falhando;
- senha, token ou chave hardcoded;
- rota admin acessível por usuário comum;
- MFA/step-up ou reautenticação de operação administrativa sensível ausente;
- quota/fallback sem teste;
- encoding corrompido;
- APK sem assinatura de produção;
- versão ou package ID divergente;
- APK do link com tamanho/hash diferente;
- servidor sem suporte a retomada;
- Telegram apontando para versão antiga;
- manifesto de proveniência ou SBOM ausente/divergente;
- backend incompatível com APK N−1/N−2;
- app não instala, não abre, pede reparo ou não gera em dispositivo real.

## 32. Rollout e rollback

### Rollout

1. Congelar escopo e registrar commit/versão.
2. Backup e teste de restauração.
3. Validar migration em cópia compatível.
4. Publicar backend rolling.
5. Confirmar migration, health e métricas.
6. Smoke de auth/admin/geração.
7. Construir APK do mesmo commit.
8. Assinar e registrar hash.
9. Disponibilizar no endpoint estável.
10. Baixar novamente, validar hash/assinatura e instalar.
11. Atualizar Telegram.
12. Monitorar erros e geração.

### Rollback

- Backend: restaurar imagem anterior compatível.
- Banco: aplicar procedimento definido pela migration ou restore.
- APK: restaurar artefato anterior somente se compatível com o schema.
- Telegram: apontar para o último APK comprovadamente saudável.
- Secrets: revogar/rotacionar, nunca restaurar um segredo comprometido.
- Acionar rollback por aumento de erro, login/geração indisponível,
  corrupção, cobrança ou falha de instalação.

## 33. Entregáveis

- Inventário completo do sistema.
- Matriz mestre de auditoria.
- `audit/AUDIT_CONTROL_MATRIX.json` aprovado em modo estrito.
- Relatório de achados com severidade e reprodução.
- Evidências sanitizadas.
- Testes de regressão adicionados.
- Registro de correções e retestes.
- Relatório de segurança e dependências.
- Relatório de acessibilidade.
- Relatório de performance.
- Relatório de migration/backup/restore.
- Manifesto do release com versão, assinatura, tamanho e hash.
- Resultado de instalação e geração em celular real.
- Riscos residuais e aceite explícito.

## 34. Cadência após a auditoria inicial

- A cada alteração: lint, testes focados e revisão do domínio.
- A cada PR/release: regressão, segurança, migration e release gates.
- Semanal: saúde, erros, quotas, fallback e custos de IA.
- Mensal: dependências, secrets, permissões, backup/restore e acessibilidade.
- Trimestral: auditoria 360° reduzida e exercício de incidente.
- Anual ou após incidente grande: auditoria 360° completa.

## 35. Critério final de encerramento

A auditoria só pode ser encerrada com uma tabela final contendo todos os IDs,
status, evidências e riscos residuais. “Não testado”, “não aplicável” e
“aceito” exigem justificativa e aprovação explícita. Ausência de evidência
equivale a falha.

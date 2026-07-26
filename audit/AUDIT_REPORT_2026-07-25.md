# Relatório da Auditoria 360° — 25/07/2026

**Plano aplicado:** `docs/MASTER_SYSTEM_AUDIT_PLAN.md` v1.1
**Aplicação:** Quiz Vance 2.0.35+34
**Commit de referência:** `c37c842f28451d6e04498b6ff86ce50619e75486`
**Resultado:** **REPROVADO — Gate 0 bloqueado**
**Regra:** nenhum item sem prova foi marcado como aprovado.

## 1. Resumo executivo

A auditoria encontrou riscos que impedem considerar a versão segura ou pronta
para promoção:

- credencial do bot Telegram exposta em arquivos e passível de persistência em
  logs/PostgreSQL por exceções HTTP;
- confirmação de checkout capaz de liberar Premium sem validação do pagamento;
- 429 de provedor classificado no aplicativo como falta de plano/cota do usuário,
  reproduzindo a classe do incidente relatado;
- resultados anunciados como salvos offline sem persistência real;
- falhas do keystore SQLCipher silenciadas, com risco de tornar o banco local
  ilegível;
- CI incapaz de provar flavor production, assinatura, hash ou proveniência;
- árvore de trabalho extremamente divergente do commit de referência;
- gates de supply chain, compatibilidade N−1/N−2, restore e aparelho real ausentes.

Os testes existentes passam, mas não cobrem os riscos críticos encontrados.

## 2. Estado dos gates

| Gate | Estado | Motivo |
|---|---|---|
| 0 — Segurança imediata | **Falhou/P0** | Segredos Telegram expostos e exceções podem persistir o token |
| 1 — Inventário/proveniência | **Falhou/P1** | 53 componentes classificados, 263 ainda sem classificação; proveniência incompleta |
| 2 — Domínios | **Não aberto** | Gate 0 impede aprovação; revisão exploratória registrou achados |
| 3 — Correções | **Não iniciado** | Auditoria read-only; correção exige autorização de implementação |
| 4 — Regressão total | **Parcial** | Suites passaram; faltam contratos, E2E real, concorrência e dispositivo |
| 5 — Release/produção | **Falhou/P1** | Sem proveniência/CI confiável e sem instalação/geração em aparelho real |

## 3. Baseline e evidências automatizadas

### Aprovado

- `flutter analyze --no-pub`: sem ocorrências.
- `flutter test --no-pub`: **269 testes aprovados**.
- `pytest backend/tests -q`: **11 testes aprovados**.
- `compileall`: aprovado.
- `alembic heads`: head único `20260725_17`.
- `pip check`: nenhuma dependência quebrada.
- fontes Flutter sem mojibake real ou `U+FFFD`.
- produção `/health/ready`: 200, banco `up`.
- fake login com payload válido: 401.
- rota admin sem JWT: 401.
- geração sem JWT: 401.
- APK latest: HEAD 200, tamanho 43.242.330, `Accept-Ranges`.
- Range válido: 206; hash público igual ao artefato local.
- APK assinado por certificado de produção, schemes v1/v2 válidos.
- modelos atuais verificados nas documentações oficiais de Google, OpenAI e Groq.

### Reprovado ou indisponível

- Ruff backend: **167 ocorrências** no escopo app/tests/scripts.
- Bandit: 1 alerta médio em `backend/app/mercadopago.py:67`.
- `pip-audit` e `gitleaks`: indisponíveis.
- nenhum `integration_test/` real.
- nenhum teste em aparelho físico.
- nenhum sandbox completo de Mercado Pago.
- nenhum teste com provedores reais de IA/corpus dourado.
- nenhum ensaio de backup/restore, rollback avançado ou concorrência PostgreSQL.

## 4. Achados P0

### P0-001 — Credenciais Telegram/admin expostas em arquivos

**Arquivos:**

- `scripts/upload_apk_telegram.py:8`
- `scripts/upload_apk_telegram.py:33`
- `scripts/get_tele_token.ps1:12`
- `telegram_bridge/.env`

O script de upload contém token do bot e prepara mensagem com credencial
administrativa. O helper imprime segredo em texto puro. O script está rastreado
e staged; o `.env` está presente como untracked. Rotação/revogação não foi
comprovada.

**Impacto:** takeover do bot, publicação de APK/link adulterado e acesso
administrativo indevido.

**Controles:** `AUDIT-23-001`, `AUDIT-23-005`, `AUDIT-28-001`,
`AUDIT-28-011`.

### P0-002 — Erro do Telegram pode gravar token no banco e logs

**Arquivos:**

- `backend/app/telegram_bot.py:904-912`
- `backend/app/main.py:485-506`
- `backend/app/main.py:624-632`
- `backend/app/main.py:698-706`

A URL contém `bot<TOKEN>`. `httpx.raise_for_status()` inclui a URL na exceção,
enquanto o backend persiste `str(ex)` em `last_error` e registra traceback.
Prova sintética confirmou a propagação do marcador secreto na mensagem.

**Ação de contenção obrigatória:** rotacionar token, remover credenciais dos
arquivos, sanitizar URL/exceção e limpar ocorrências históricas de logs e banco.

**Controles:** `AUDIT-23-001`, `AUDIT-27-006`, `AUDIT-28-001`,
`AUDIT-28-013`.

## 5. Achados P1 — bloqueadores de release

### P1-001 — Premium pode ser ativado sem pagamento verificado

`backend/app/main.py:1716-1748` e `backend/app/services.py:458-523` aceitam
`tx_id/provider` fornecidos pelo cliente e não consultam o Mercado Pago. Prova
isolada confirmou ativação com transação arbitrária.

### P1-002 — Valor/moeda/plano divergentes podem ser aceitos

`backend/app/services.py:526-605` não compara o pagamento recebido com o
checkout. Prova isolada confirmou aceitação de 1 centavo em USD para Premium.

### P1-003 — Webhook Mercado Pago usa autenticação incompatível

`backend/app/main.py:1053-1058`, `1641-1644` e `1908-1911` não validam
`x-signature`/`x-request-id` conforme o contrato oficial. Com secret próprio
configurado, evento legítimo pode receber 403; sem secret, o fluxo falha aberto.
Referência: [Mercado Pago — Webhooks](https://www.mercadopago.com.br/developers/pt/docs/your-integrations/notifications/webhooks).

### P1-004 — Webhook genérico perde retry em falha parcial

`backend/app/main.py:1867-1903` commita `WebhookEvent` antes de Payment/Premium.
Falha posterior faz o retry ser tratado como já processado.

### P1-005 — Admin sensível não exige MFA/step-up

`backend/app/routers/admin_ai.py:77-215` permite criar, rotacionar, ativar e
excluir chaves com apenas JWT administrativo. RBAC existe, mas não atende ao
bloqueador `AUDIT-10-013/014`.

### P1-006 — Webhook Telegram falha aberto sem secret

`backend/app/main.py:1061-1068`, `1246-1261` e `309-335` aceitam requisição
quando o secret não está configurado; payload de grupo pode alterar o chat alvo.

### P1-007 — Todo HTTP 429 vira falta de Premium

**Arquivos:** `quiz_repository.dart:41-49`,
`simulado_repository.dart:39-47`, `open_quiz_repository.dart:38-46`.

Rate limit do provedor, crédito da chave e quota do usuário tornam-se
`PremiumLimitException`; as telas descartam o detalhe e abrem upsell. Isso
reproduz “sem cota mesmo tendo cota”. Os testes atuais codificam o comportamento
incorreto.

### P1-008 — Resultado offline prometido, mas não persistido

`quiz_result_screen.dart:103-138` e `simulado_result_screen.dart:52-96`
informam que o resultado foi salvo/sincronizará, mas não gravam nem enfileiram.
Sair ou matar o app perde resultado, XP e histórico.

### P1-009 — Falha do keystore pode tornar SQLCipher ilegível

`local_storage.dart:682-704` silencia falhas de leitura/escrita, usa chave nova
mesmo sem persistência e `main.dart:84-92` abre o app após falha do storage.

### P1-010 — SRS reinicia a cada revisão e sync pode sobrescrever dados

`flashcard_repository.dart:53-104` ignora estado anterior, usa sync
fire-and-forget e não reprocessa `synced=0`. Revisão local pode ser sobrescrita.

### P1-011 — Migração/reordenação admin não são atômicas

`admin_master_keys_service.dart:115` pode duplicar importação após falha parcial;
`admin_master_keys_service.dart:177` aplica prioridades por PATCH sequencial.

### P1-012 — Release sem proveniência reproduzível

A árvore possui centenas de mudanças staged/unstaged/untracked. Backend,
migration, imagem Fly, APK e Telegram não estão ligados por manifesto imutável.

### P1-013 — CI pode publicar artefato errado ou debug-signed

`.github/workflows/build.yml:75` não seleciona flavor production nem injeta
`APP_VERSION`; `android/app/build.gradle:103-107` cai para assinatura debug se
`key.properties` faltar.

### P1-014 — CI contradiz APK universal e depende de Windows removido

O workflow publica splits e exige Windows, enquanto o canal oficial é universal
e o diretório Windows está staged para remoção.

### P1-015 — Supply chain sem gates mínimos

Não há CI de backend, Ruff, Bandit, migration, SBOM, scan de container,
assinatura/hash ou actions pinadas. Docker usa base mutável e root.

### P1-016 — Migration acoplada ao startup

`backend/Dockerfile:19` executa Alembic antes de cada Gunicorn, permitindo
concorrência em scale/start. Downgrade da migration 17 remove dados sem restore
comprovado.

### P1-017 — Sem compatibilidade N−1/N−2

Aceitar `X-App-Version` não prova contrato/payload/schema com APK antigo.
Não existe teste antes/depois de migration e rollback.

### P1-018 — Artefatos/entrypoints antigos podem republicar APK errado

`output_apk/app-universal-release.apk` é 2.0.14+8; teste de entrypoint exige
2.0.14+8; publicador legado aponta para 2.0.15+9; há APKs antigos staged.

### P1-019 — Publicação Telegram não é atômica

O publicador valida hash local, não o URL remoto. Em fallback, desfixa a mensagem
antiga antes de criar/verificar a nova. Existem publicadores concorrentes por
link e anexo.

## 6. Achados P2

- recuperação de senha sem rate limit persistente, limite de tentativas e
  proteção completa contra enumeração;
- access token de 12 h reutilizado como refresh até 24 h após expirar;
- rota legada aceita senha vazia; senha atual permite apenas seis caracteres;
- quotas de IA usam check-then-increment e não reservam uso atomicamente;
- XP e conquistas são aceitos do cliente;
- alteração de login não exige senha nem revoga sessões;
- rate limiter em memória/IP, reiniciável e não distribuído;
- mesmo segredo assina sessão, cifra cofre e autoriza rotas internas;
- CORS `*` com credenciais e headers de segurança incompletos;
- payloads de pagamento/PII sem retenção/minimização comprovadas;
- migration `CREATE TABLE IF NOT EXISTS` pode mascarar schema parcial;
- fila offline descarta item após cinco falhas sem dead-letter;
- cronômetro de simulado não reconcilia tempo ao voltar do background;
- importação confia em extensão/MIME e carrega até 50 MB antes do isolate;
- alvos de toque de 34×34 dp, semântica TalkBack e estados selecionados
  insuficientes;
- contraste aproximado de `textMuted` e `primary` abaixo do alvo em fundos
  usados;
- redução de movimento não respeitada;
- exceções internas ainda interpoladas diretamente em telas;
- retry de geração sem idempotency key e fallback pode remover o contexto;
- rota versionada do APK retorna 405 para HEAD;
- Fly com 256 MB, auto-stop e indício de OOM não investigado;
- APK de 43 MB sem minify/shrink;
- branch protection não comprovada.

## 7. Evidências positivas de implementação

- admin é promovido a partir de conta existente e `auth_version` muda;
- rotas admin exigem JWT/role;
- chaves mestras são cifradas e mascaradas;
- circuit breaker/fallback do pool possui persistência e testes;
- logout/reset revogam sessões por `auth_version`;
- lembrar login possui persistência e testes;
- router bloqueia `/admin/*` para usuário comum;
- SQLCipher, isolamento local por conta e cleartext Android bloqueado;
- APK local/latest/versionado possuem mesmo tamanho/hash;
- assinatura e continuidade do certificado verificadas;
- package/version/minSdk/targetSdk/quatro ABIs verificados;
- `zipalign`, GET/HEAD/latest, 206 e 416 aprovados;
- Fly health/readiness e imagem ativa aprovados.

## 8. Lacunas obrigatórias

- instalação limpa/upgrade/abertura/login/geração em aparelho real;
- Telegram fixado real e mensagem anexada verificados visualmente;
- backup/restore, PITR, RPO/RTO e rollback com schema avançado;
- concorrência PostgreSQL para quota, webhook, checkout e chave;
- sandbox Mercado Pago, assinatura real, chargeback e reconciliação;
- e-mail real, SPF/DKIM/DMARC, bounce e spam;
- provedores reais de IA, custos, latência e corpus dourado;
- DAST/fuzz, CVEs, SBOM e histórico Git completo;
- LGPD, retenção, subprocessadores e atendimento ao titular;
- TalkBack, Accessibility Scanner, golden tests e matriz de dispositivos;
- branch protection e políticas autenticadas do repositório.

## 9. Ordem obrigatória de resposta

1. Rotacionar/revogar token Telegram e credenciais administrativas expostas.
2. Remover segredos de arquivos/índice e sanear logs/`last_error`.
3. Fechar fraude de checkout e autenticar webhook Mercado Pago oficialmente.
4. Corrigir classificação 429 e separar quota do usuário de quota/rate limit da IA.
5. Corrigir persistência offline, keystore e SRS.
6. Congelar fonte canônica/árvore limpa e criar manifesto de proveniência.
7. Corrigir CI, assinatura, artefatos antigos, supply chain e migrations.
8. Executar regressão, E2E, sandbox, backup/restore e dispositivo real.

## 10. Veredito

A auditoria de hoje não autoriza novo release. A versão publicada pode continuar
disponível apenas como artefato de teste controlado, mas o token Telegram deve
ser tratado como comprometido e o fluxo de billing não deve ser promovido para
uso financeiro real antes das correções e retestes.

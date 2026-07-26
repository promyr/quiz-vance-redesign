# Relatório de remediação da auditoria — 25/07/2026

**Referência:** `audit/AUDIT_REPORT_2026-07-25.md`
**Escopo:** correções locais de aplicação, backend, segurança e release
**Versão validada:** `2.0.36+35`
**Estado:** **correções locais concluídas; promoção externa ainda bloqueada**

## Resultado executivo

Os bloqueadores de código P0/P1 foram corrigidos e cobertos por regressão. O
APK de produção foi reconstruído com assinatura fail-closed e validado
localmente. Nenhum deploy, alteração no Telegram ou promoção para produção foi
executado nesta etapa.

A promoção continua bloqueada até concluir os controles que dependem de
credenciais ou ambientes externos: rotação do token Telegram, configuração dos
novos segredos, migração/restore em staging, concorrência PostgreSQL real,
sandbox Mercado Pago e teste em aparelho físico.

## Correções aplicadas

### Segurança e credenciais

- segredos removidos do workspace e do índice Git;
- `.env` ignorado, mantendo somente `.env.example`;
- gate automatizado de higiene de segredos adicionado ao CI;
- erros Telegram sanitizados antes de logs e `last_error`;
- webhooks Telegram e Mercado Pago agora falham fechados;
- mutações administrativas exigem senha recente em memória;
- alteração de login exige senha atual e revoga sessões;
- access e refresh tokens foram separados, tipados e rotativos;
- sessão, cifra e segredo interno possuem configurações separadas e suporte a
  rotação por chaves anteriores.

### Billing, quotas e integridade

- confirmação manual de checkout não ativa Premium;
- pagamento valida provedor, valor, moeda e plano;
- idempotência rejeita transações divergentes;
- evento, pagamento e ativação são persistidos atomicamente;
- assinatura oficial do webhook Mercado Pago é validada;
- quotas diárias e semanais são reservadas atomicamente;
- rate limit usa PostgreSQL em produção e falha fechado quando indisponível;
- IDs, elegibilidade, XP e recompensas de conquistas são calculados no servidor;
- payload de webhook é minimizado e possui retenção definida.

### Flutter e experiência

- 429 de quota do produto foi separado de rate limit/crédito do provedor;
- resultados offline são persistidos com idempotência, retry e dead-letter;
- falhas do keystore interrompem o bootstrap em tela segura de recuperação;
- SRS progride do estado anterior e sincroniza reviews de forma durável;
- cronômetro do simulado usa deadline real e reconcilia background;
- importação limita bytes antes da leitura e valida MIME, assinatura PDF e
  conteúdo binário disfarçado;
- fluxos administrativos e troca de login foram alinhados ao backend;
- alvos de toque, semântica, live region, contraste e redução de movimento foram
  reforçados nos fluxos apontados pela auditoria.

### Release e supply chain

- CI usa Actions fixadas por SHA;
- backend executa pytest, Ruff crítico, Bandit, compileall e Alembic;
- container possui usuário não-root, SBOM e scan no pipeline;
- migration saiu do startup e foi movida para `release_command`;
- Android gera somente APK universal `production`;
- assinatura de produção falha fechado sem keystore;
- pipeline verifica zipalign, assinatura, certificado, manifesto e SHA-256;
- publicador Telegram verifica tamanho e hash do download público antes de
  alterar a mensagem e preserva o pin antigo até a nova publicação ser válida;
- endpoint versionado do APK aceita GET e HEAD;
- manifesto de proveniência de release foi documentado.

## Evidências locais

| Controle | Resultado |
|---|---|
| `flutter analyze --no-pub` | aprovado, 0 ocorrências |
| `flutter test --no-pub` | aprovado, 284 testes |
| `pytest backend/tests -q` | aprovado, 30 testes |
| Ruff crítico (`E9,F63,F7,F82`) | aprovado |
| Bandit médio/alto | aprovado |
| `compileall` | aprovado |
| `pip check` | aprovado |
| Alembic | head único `20260725_18` |
| higiene de segredos | aprovado, 0 achados |
| matriz de auditoria estrutural | aprovada, 254/254 requisitos presentes |
| política de release/entrypoint | aprovada |
| APK production universal | gerado, 43.307.891 bytes |
| APK SHA-256 | `9708E3DDE3FF1095C0FBE1A419E115ECB0A394EAAB29F154957C1DC65999D64A` |
| assinatura APK | v1/v2 válidas |
| certificado SHA-256 | `b039a11e96aafa7107be445bd6404516ada37962c0b735c059939ea15ca67215` |
| package/version | `com.quizvance.quiz_vance_flutter`, `2.0.36+35` |
| SDK | min 21, target 34 |

Artefato local:
`output_apk/quiz-vance-2.0.36+35-universal.apk`.

## Gates externos ainda obrigatórios

1. Revogar e rotacionar o token comprometido no BotFather.
2. Limpar ocorrências históricas em logs e `last_error` de produção.
3. Configurar `MP_WEBHOOK_SECRET`, `TELEGRAM_WEBHOOK_SECRET`,
   `SESSION_SIGNING_SECRET`, `INTERNAL_API_SECRET` e `DATA_ENCRYPTION_KEY`.
4. Executar migration 18, backup/restore e rollback em staging.
5. Executar ensaio concorrente em PostgreSQL e sandbox completo Mercado Pago.
6. Executar build/SBOM/scan real no CI com Docker.
7. Instalar e testar em aparelho real: instalação limpa, upgrade, login,
   geração, offline, background e download Telegram.
8. Verificar políticas autenticadas do repositório e branch protection.

## Pendências de qualidade não bloqueadoras do código crítico

- o lint Ruff completo está limpo; falsos positivos estruturais de FastAPI,
  fronteiras externas e parsing tolerante estão documentados em
  `backend/ruff.toml`;
- a árvore de trabalho contém mudanças anteriores do usuário e deve ser
  consolidada em um commit/release canônico antes da promoção;
- testes de provedores reais de IA, e-mail, DAST/fuzz, LGPD e matriz ampla de
  dispositivos continuam dependendo de ambientes e processos externos.

## Veredito

O código corrigido está apto para avançar ao **staging controlado**, mas não
está autorizado para deploy ou publicação oficial enquanto os gates externos
acima não forem comprovados.

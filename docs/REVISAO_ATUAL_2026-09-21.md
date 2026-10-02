# Revisão do Quiz Vance — 21/09/2026

## Parecer

A versão local 2.0.64+63 não está aprovada para uma nova publicação. Há falhas reproduzidas no backend e defeitos de fluxo identificados no código que a suíte Flutter atual não cobre. Esta revisão não alterou código, credenciais, banco de produção ou publicações.

Escopo: árvore local completa (HEAD `27b3d00`, de 04/09/2026, mais alterações locais), APK disponível, autenticação/biometria, documentos/planos, chaves de IA, configuração de infraestrutura, testes e publicação Telegram. Não equivale a uma auditoria exaustiva de todos os recursos nem a um teste em aparelho físico.

## Evidências de versão e validação

- `pubspec.yaml`, `AppConfig` e metadados internos do APK: **2.0.64+63**.
- APK: `output_apk/quiz-vance-2.0.64+63-universal.apk`, 40.315.054 bytes; SHA-256 `E60320961643534366558250971874034700D83D443F9CA1CCC79AD42BB8FCDB`.
- Assinatura verificada: CN=Quiz Vance; certificado SHA-256 `B039A11E96AAFA7107BE445BD6404516ADA37962C0B735C059939EA15CA67215`.
- Android: mínimo 24, target e compile SDK 36. Não foi feita instalação.
- URL Render encontrada nas três bibliotecas `libapp.so` do APK; URL Fly ausente nessas bibliotecas. O padrão do código e `backend_url.txt` também apontam para Render.
- Manifesto local de release ainda aponta para **2.0.61+60**, hash e commit antigos.
- `flutter analyze --no-pub`: aprovado. `flutter test --no-pub --reporter expanded`: **367 aprovados**.
- Ruff: **3 violações** — `os` indefinido em `security.py`, import `json` ocioso e captura genérica em `smart_cache_service.py`.
- Pytest: **115 aprovados, 16 falhas**. Quinze falhas são no caminho de criptografia com `NameError: os`; uma é de expectativa CORS. O teste CORS passou isoladamente com `ENVIRONMENT=test`, indicando configuração de teste inconsistente, não motivo para abrir CORS de produção.
- Os testes backend usaram SQLite isolado fora do projeto. Ambiente local contém FastAPI 0.116.1, Pydantic 2.11.7, Starlette 0.47.3 e cryptography 45.0.7; não coincide com os pins de `requirements.txt` (FastAPI 0.140.0, Pydantic 2.13.4, cryptography 48.0.1). Portanto não valida integralmente a imagem de produção.
- Consultas públicas: Render `/health/ready` expirou sem resposta em 45 e 35 segundos. Fly `/health/ready` respondeu 200; `/app/update` respondeu 200 anunciando **2.0.55+54**. Isso comprova indisponibilidade nas tentativas realizadas, não determina a causa do problema no Render.
- Estado inicial do Git: 122 caminhos modificados, 16 removidos e 102 entradas não rastreadas. Não é possível atribuir o APK a todo esse conteúdo sem um manifesto correspondente.

## Achados prioritários

### R01 — Crítico: credencial do bot no código versionado

**Evidência:** `scripts/publish_telegram_v64.ps1:2` contém um token literal; o arquivo é rastreado por Git. O valor foi redigido durante a inspeção e não foi usado para chamadas.

**Impacto:** acesso ao repositório, histórico ou cópia do script pode expor controle do bot, caso o token ainda seja válido.

**Recomendação:** revogar/rotacionar a credencial pelo canal administrativo, atualizar armazenamento seguro e retirar o segredo do código. Avaliar o histórico e o detector de segredos. A validade atual do token não foi testada.

### R02 — Alto: criptografia de chaves de IA lança exceção

**Evidência:** `backend/app/security.py:21` usa `os.getenv`, mas não importa `os`. Chamadas de criação de chave e criptografia falharam nos testes; Ruff também identifica F821.

**Impacto:** cadastrar/atualizar chaves pelo administrador falha. Ler chaves criptografadas passa pela mesma derivação, comprometendo o pool de IA.

**Recomendação:** corrigir o import e validar criação, leitura, edição, rotação e uso do pool. Não basta considerar esse ajuste como resolução de R03.

### R03 — Alto: mudança da derivação invalida segredos anteriores

**Evidência:** `backend/alembic/versions/20260328_15_security_hardening.py:53` deriva com `salt=None` e contexto `quiz-vance:user-settings:api-keys:v1`. `backend/app/security.py:10` e `:21` usam outro contexto e salt não vazio, mas mantêm o prefixo `enc:v1:`. `backend/app/services.py:372` tenta outras chaves, sem restaurar o esquema de derivação antigo.

**Impacto:** dados cifrados pelo esquema anterior não podem ser decifrados pelo atual, mesmo após resolver R02 e mantendo a chave mestra original. Configurar outro salt também altera a chave derivada.

**Recomendação:** implementar leitura compatível por versão e migração controlada/recriptografia; testar um ciphertext produzido pelo esquema antigo. Preservar as chaves anteriores até confirmar a migração.

### R04 — Alto: digital pode autenticar conta diferente da exibida

**Evidência:** `lib/shared/providers/auth_provider.dart:102` tenta recadastrar a biometria após login por senha, mas ignora cancelamento/falha em `:118`. `loginWithBiometrics` recebe `loginId`, porém não o confere contra o cofre (`:135`). O nome do botão vem do cache em `lib/features/auth/presentation/login_screen.dart:55`.

**Cenário:** cofre da conta A; login por senha na conta B; cancelamento do recadastro. O cache exibe B, mas o cofre ainda pode conter A. A digital usa o token de A.

**Recomendação:** vincular a identidade do cofre à conta reconhecida, invalidar o vínculo na troca de conta e conferir a identidade antes de aceitar o desbloqueio. Criar teste com duas contas e cadastro cancelado.

### R05 — Alto: opção de não lembrar login é desrespeitada

**Evidência:** `login_screen.dart:207` envia `rememberSession` e, independentemente dele, `enrollBiometrics`. Em `auth_provider.dart:81` o cofre é limpo quando lembrar está desmarcado; em `:102` pode ser cadastrado novamente com o refresh token recebido.

**Impacto:** uma credencial reutilizável pode continuar persistida apesar da escolha do usuário.

**Recomendação:** exigir `rememberSession && enrollBiometrics` na camada de autenticação, além do comportamento coerente da interface. Testar ausência de cofre após login sem persistência.

### R06 — Alto: plano legado pode bloquear o carregamento indefinidamente

**Evidência:** `lib/features/study_plan/data/study_plan_repository.dart:43` chama `getActivePlan()` quando a lista está vazia. A migração em `:73` chama `savePlan()`, que chama `getPlans()` em `:95` antes de gravar a lista.

**Cenário:** existe `study_plan_active`, mas ainda não existe `study_plans_all`. O ciclo assíncrono não alcança a escrita que encerraria a migração.

**Recomendação:** migrar diretamente para a persistência interna, sem reentrar no método que faz fallback. Testar atualização de instalação antiga, não apenas preferências vazias.

### R07 — Alto: edital concluído não abre depois de retornar à tela

**Evidência:** `backend/app/routers/documents.py:186` lista documentos sem resultado (`analysis_result=null` em `:88`). A tela restaura essa lista e, ao selecionar um documento pronto, chama `_applyReadyDocument` diretamente (`study_plan_screen.dart:244`). Sem análise, `:359` apresenta erro de ausência de disciplinas.

**Impacto:** o servidor pode concluir o trabalho em segundo plano, mas a interface não recupera seu resultado quando o usuário volta.

**Recomendação:** buscar o detalhe do documento pronto antes de aplicá-lo. Testar concluir → sair → voltar → selecionar → gerar plano.

### R08 — Alto: filtro de páginas exclui matérias presentes no PDF

**Evidência:** `backend/app/document_processing.py:331` escolhe `cargo_indexes or generic_indexes`. Encontrar o nome do cargo elimina todas as páginas de conteúdo programático fora da vizinhança dessas ocorrências.

**Reprodução local:** cargo na página 1 e programa na página 10 resultaram apenas nas páginas `[1, 2, 3]` selecionadas.

**Impacto:** erro de matérias não encontradas ou plano incompleto, apesar de a extração de texto funcionar.

**Recomendação:** identificar blocos programáticos completos, inclusive anexos e conteúdo comum aplicável, com associação ao cargo e evidência de páginas. Cobrir esse formato real de edital nos testes.

### R09 — Alto: disponibilidade e persistência do destino atual não estão comprovadas

**Evidência:** código e APK apontam para Render; duas consultas de readiness expiraram. O CI usa Fly como fallback em `.github/workflows/build.yml:23`. `render.yaml:17` define armazenamento em `/tmp/study_documents`, sem disco persistente no blueprint; `DocumentStorage` grava PDFs no filesystem local.

**Impacto:** builds locais e de CI podem usar servidores diferentes. Se o blueprint for usado sem persistência adicional, substituição do container perde os PDFs necessários a extração/reprocessamento, apesar de registros no banco permanecerem.

**Recomendação:** definir um destino canônico, investigar disponibilidade com logs do Render e confirmar armazenamento durável e testes de retomada após reinício/deploy. Não foi inspecionada a configuração privada efetiva do Render, logo não se afirma que arquivos já foram perdidos.

### R10 — Médio: timeout de IA não aciona retomada automática

**Evidência:** `backend/app/admin_ai.py:292` reconhece `TimeoutError`, mas não `httpx.TimeoutException`. `httpx.ReadTimeout` foi classificado como `provider_error` em reprodução local; `document_worker.py:143` não considera esse código transitório.

**Impacto:** após esgotar candidatos com timeout HTTP, um documento pode falhar definitivamente em vez de aguardar e retomar dos checkpoints.

**Recomendação:** classificar explicitamente timeouts e falhas transitórias de transporte; testar com as exceções reais do cliente HTTP.

### R11 — Médio: exclusão de PDF da Biblioteca não persiste

**Evidência:** `library_repository.dart:84` apaga somente a cópia local. `library_document_recovery.dart:31` recupera todos os documentos remotos prontos e os importa novamente.

**Impacto:** material removido reaparece ao reabrir a Biblioteca.

**Recomendação:** coordenar exclusão remota/local ou guardar marcador de exclusão respeitado pela recuperação, inclusive em falha de rede.

### R12 — Médio: restauração, desbloqueio e logout estão inconsistentes

**Evidência:** `auth_provider.dart:27` sempre retorna desautenticado no boot; `confirmSavedSession()` não tem chamadores em `lib`. `login_screen.dart:513` sempre constrói o formulário completo, com botão biométrico inserido no mesmo fluxo; `AuthScreenMode` está sem uso. Em `auth_provider.dart:247`, logout só limpa o cofre quando solicitado explicitamente, enquanto o backend revoga a sessão.

**Impacto:** sessão válida lembrada não é restaurada automaticamente; a separação solicitada entre desbloqueio e outra conta foi abandonada; após logout pode aparecer um atalho biométrico com token revogado.

**Recomendação:** separar estados válida/bloqueada/expirada, implementar as transições exclusivas e distinguir bloquear de sair. Atualizar os testes, que atualmente aceitam o formulário simultâneo à ação biométrica.

### R13 — Alto: publicação pode anunciar sucesso sem envio validado

**Evidência:** `scripts/publish_telegram_v64.ps1:68` envia ao Telegram, imprime o retorno e termina em `:86` anunciando sucesso, sem validar código HTTP, `ok`, documento e tópico retornados. O destino é fixado em `:4` como tópico 6; o publicador do backend usa registro no banco e mantém host Fly. Não foi estabelecido nesta revisão qual ID corresponde ao tópico visível Atualizações.

**Impacto:** falhas de rede, permissão ou Telegram podem ser apresentadas como publicação concluída. O caminho atual também contorna o manifesto de release, ainda antigo.

**Recomendação:** unificar a publicação; validar versão interna, assinatura, hash e resposta do Telegram; conferir nome/destino do tópico e fornecer link direto da mensagem como evidência. Nenhum arquivo foi reenviado, fixado ou excluído nesta revisão.

## Ordem proposta de correção

1. Conter a exposição da credencial do bot e resolver R02/R03 com compatibilidade de criptografia e testes do pool.
2. Resolver identidade e persistência biométrica (R04/R05), depois restauração/logout (R12).
3. Resolver migração legada, reabertura do documento e seleção de matérias (R06–R08); corrigir retry e exclusão (R10/R11).
4. Confirmar destino e durabilidade no servidor (R09); validar sob as dependências fixadas em produção.
5. Unificar manifesto/publicação (R13) e executar teste em Android real: login, troca de conta, cancelamento, standby, atualização de instalação antiga, PDF em segundo plano e reabertura.

## Limites e preservação

O resultado de testes automatizados não demonstra operação correta de biometria nativa ou de provedores de IA reais. Não foram usados login de usuário, chaves de IA ou token do bot para validar esses recursos. Não houve build novo, deploy, mudança de conta, rotação de segredo ou postagem Telegram. A única entrega escrita é este relatório; os testes geraram seus caches e dados isolados de diagnóstico.

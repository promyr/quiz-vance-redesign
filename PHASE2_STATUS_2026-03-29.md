# Phase 2 Status - 2026-03-29

## Objetivo

Mover orquestracao de regras e fluxos criticos para camadas intermediarias de `application/`, reduzindo acoplamento entre `presentation/` e `data/`.

## Fechado nesta sessao

### Billing / Premium

- `lib/features/profile/application/premium_checkout_coordinator.dart`
- `lib/features/profile/presentation/premium_screen.dart`

Checkout premium agora passa por um coordenador dedicado, com validacao de sessao, normalizacao de nome e contrato unico de inicio de checkout.

### Biblioteca

- `lib/features/library/application/library_actions_coordinator.dart`
- `lib/features/library/presentation/library_screen.dart`

A tela deixou de orquestrar diretamente geracao de pacote e operacoes de arquivo contra repositorio/guard.

### Flashcards

- `lib/features/flashcard/application/flashcard_generation_coordinator.dart`
- `lib/features/flashcard/presentation/flashcard_hub_screen.dart`

A geracao e persistencia de flashcards foi movida para coordenador proprio, incluindo validacao da origem e escrita local.

### Quiz objetivo

- `lib/features/quiz/application/quiz_generation_coordinator.dart`
- `lib/features/quiz/presentation/quiz_config_screen.dart`

Regras de selecao de fonte, fallback de provider/contexto e limpeza de memoria agora estao centralizadas em `application/`.

### Plano de estudo

- `lib/features/study_plan/application/study_plan_coordinator.dart`
- `lib/features/study_plan/presentation/study_plan_screen.dart`

Geracao do plano e toggle persistido deixaram de ser responsabilidade direta da tela.

### Quiz dissertativo

- `lib/features/open_quiz/application/open_quiz_coordinator.dart`
- `lib/features/open_quiz/presentation/open_quiz_screen.dart`

Validacao de entrada, geracao de pergunta e correcao de resposta passaram para coordenador dedicado.

### Simulado

- `lib/features/simulado/application/simulado_generation_coordinator.dart`
- `lib/features/simulado/presentation/simulado_config_screen.dart`

Geracao do simulado e derivacao de `durationSeconds` ficaram encapsuladas fora da UI.

## Testes adicionados

- `test/features/profile/premium_checkout_coordinator_test.dart`
- `test/features/library/library_actions_coordinator_test.dart`
- `test/features/flashcard/flashcard_generation_coordinator_test.dart`
- `test/features/quiz/quiz_generation_coordinator_test.dart`
- `test/features/study_plan/study_plan_coordinator_test.dart`
- `test/features/open_quiz/open_quiz_coordinator_test.dart`
- `test/features/simulado/simulado_generation_coordinator_test.dart`

## Validacao executada

- `flutter analyze --no-pub lib test`
  - resultado: apenas 3 infos antigos fora do escopo desta sessao
- testes direcionados dos 7 coordenadores acima
  - resultado: todos passaram

## Pendencias residuais da Fase 2

### Limpeza de legado em `quiz_config_screen.dart`

O fluxo novo ja esta ativo via `quizGenerationCoordinatorProvider`, mas o arquivo ainda carrega um bloco legado morto que deve ser removido por completo numa limpeza dedicada, sem alterar comportamento.

### Providers compartilhados ainda muito responsaveis

- `lib/shared/providers/auth_provider.dart`
- `lib/shared/providers/user_provider.dart`

Esses providers ainda concentram bootstrap, cache e sincronizacao demais para a camada compartilhada. O proximo passo e separar bootstrap/autenticacao e cache/stats em servicos/coordenadores dedicados.

### Acesso direto a storage fora do dominio

- `lib/shared/providers/user_provider.dart`
- `lib/features/library/presentation/study_package_screen.dart`

Ainda ha pontos acessando `LocalStorage` fora de um boundary de repositorio/coordenador.

### Telas grandes que continuam exigindo particionamento

- `lib/features/profile/presentation/premium_screen.dart`
- `lib/features/profile/presentation/profile_screen.dart`
- `lib/features/library/presentation/library_screen.dart`
- `lib/features/study_plan/presentation/study_plan_screen.dart`

Apesar da extracao de fluxo, essas telas ainda merecem reducao adicional de tamanho e decomposicao de widgets/sections.

## Backlog sugerido para Fase 3

1. Consolidar ownership de persistencia por dominio e reduzir uso espalhado de `SharedPreferences` e `LocalStorage`.
2. Extrair bootstrap de auth e cache de stats para servicos de aplicacao.
3. Adicionar testes de widget para fluxos criticos de auth, quiz, premium e biblioteca.
4. Endurecer acessibilidade dos widgets compartilhados com foco/teclado/semantics.
5. Adicionar observabilidade de produto e falha: analytics, tracing basico e crash reporting.

## Bloqueio operacional atual

O build Windows nao foi revalidado ao final desta sessao porque o host ficou com espaco insuficiente no drive `C:` durante a compilacao nativa do `sqlcipher_flutter_libs`.

Erro observado:

- `System.IO.IOException: Espaco insuficiente no disco`

Antes de repetir `flutter build windows`, liberar espaco suficiente no `C:` para o toolchain nativo.

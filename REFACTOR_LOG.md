# Relatório de Refatoração — Quiz Vance
## Data: 2026-03-23

## Problemas encontrados: 7
- CRÍTICOS: 2
- ALTOS: 1
- MÉDIOS: 3
- BAIXOS: 1

---

## Implementados nesta sessão

### [1] Study Plan — Mismatch no corpo da requisição
- **Arquivo(s):** `lib/features/study_plan/data/study_plan_repository.dart`
- **Problema:** O método `generatePlan()` enviava ao backend campos com nomes errados: `objetivo`, `topicos`, `tempo_diario` (minutos) e `data_prova`. O backend FastAPI esperava `goal`, `topics`, `hours_per_week` e `weeks`. Como resultado, o backend ignorava todos os campos do Flutter e gerava um plano com parâmetros default ("concurso publico geral", 4 semanas, 10h/semana), completamente desconectado da intenção do usuário.
- **Solução:** Mapeamento correto dos campos: `objetivo → goal`, `topicos → topics`, `tempo_diario (min) * 7 / 60.0 → hours_per_week`. Adicionados `weeks: 4` e `level: 'iniciante'` como defaults explícitos.
- **Impacto:** Plano de estudos gerado agora reflete de fato o objetivo e os tópicos informados pelo usuário.

### [2] Study Plan — Mismatch no campo de resposta (TypeError não capturado)
- **Arquivo(s):** `lib/features/study_plan/data/study_plan_repository.dart`
- **Problema:** Flutter lia `r.data['itens']` mas o backend retorna a lista em `r.data['semanas']`. Como o campo `itens` não existe na resposta, o cast `r.data['itens'] as List<dynamic>` lançava um `TypeError`. Este erro não era capturado pelo `on DioException` do repositório, propagando como exceção não tratada e crashando o fluxo de geração do plano.
- **Solução:**
  - Leitura robusta do campo: `r.data['semanas'] ?? r.data['itens'] ?? const []`
  - Adicionado bloco `catch (e)` genérico para capturar erros de parsing/cast e redirecionar para o fallback local
  - Novo método `_semanaListToItems()` que converte o formato de semanas retornado pelo backend em `List<StudyPlanItem>` (expande `tarefas` de cada semana em itens individuais com `dia`, `tema` e `atividade`)
- **Impacto:** Eliminado crash na geração do plano de estudos via API. A tela de plano de estudos agora exibe corretamente o resultado da IA em vez de quebrar ou silenciosamente usar o fallback.

### [3] Quiz Submit — stats não gravadas no backend
- **Arquivo(s):** `lib/features/quiz/data/quiz_repository.dart`, `lib/features/quiz/presentation/quiz_result_screen.dart`
- **Problema:** `QuizRepository.submit()` enviava ao backend apenas `session_id`, `answers` e `time_taken_seconds`. O backend (`/quiz/submit`) esperava também `total`, `correct` e `xp_earned` para atualizar `QuizStatsDaily`, `QuizStatsEvent` e o XP do usuário. Como esses campos não eram enviados, todos defaultavam para `0`, fazendo com que as estatísticas (questões respondidas, acertos, XP ganho) nunca fossem registradas após uma sessão de quiz.
- **Solução:**
  - Adicionados parâmetros `total`, `correct`, `xpEarned` e `topic` (opcional) ao método `submit()` do repositório
  - Esses campos agora são incluídos no corpo do POST
  - `quiz_result_screen.dart` atualizado para passar `result.total`, `result.correct`, `result.xpEarned` e `result.topic`
- **Impacto:** Estatísticas de quiz (questões, acertos, XP) agora são corretamente persistidas no backend. Ranking, histórico e stats do usuário passam a refletir as sessões de quiz real.

---

## Pendentes para próxima sessão (MÉDIO/BAIXO)

- [ ] **`UserProfile.isPremium` retorna sempre `false` para usuários premium** — `profile_repository.dart:30`: getter faz `planType == 'premium'`, mas o backend retorna `plan_code` como `"premium_30"` (nunca `"premium"`). Atualmente esse getter não é chamado em nenhuma tela (as telas usam `BillingStatus.isPremium`), então não há impacto visível — mas é um bug latente. **Fix:** mudar para `planType != 'free'` ou `planType.startsWith('premium')`. Arquivo: `lib/features/profile/data/profile_repository.dart`

- [ ] **Rota `simulado/result` sem fallback HomeScreen** — `router.dart:139`: diferente de `quiz/result` (que retorna `HomeScreen` se `result == null`), a rota `simuladoResult` passa `extra?['result']` diretamente para `SimuladoResultScreen` sem guard. Se a navegação ocorrer sem `extra`, a tela recebe `result: null` e exibe tela vazia sem back. **Fix:** adicionar guard semelhante ao `quizResult`. Arquivo: `lib/app/router.dart`

- [ ] **`StudyPlanScreen` campo `_SYSTEM_PLAN` envia `level: 'iniciante'` hardcoded** — O plano de estudos sempre gera conteúdo para iniciantes, mesmo que o usuário seja avançado. Futuramente, expor campo de nível na tela de configuração do plano e passar para `generatePlan()`. Arquivo: `lib/features/study_plan/presentation/study_plan_screen.dart`

- [ ] **`/billing/subscribe` no backend sem constante Flutter** — `routers/user.py` define `POST /billing/subscribe` mas esse endpoint não tem constante em `api_endpoints.dart` e não é chamado por nenhum repositório Flutter (o app usa `/billing/checkout/start` diretamente). Endpoint é dead code no backend. Considerar remover ou documentar como legado.

---

## Notas técnicas

**Padrão de erro recorrente — campo name mismatch entre Flutter e FastAPI:** O projeto tem dois contratos de API para o mesmo recurso em paralelo (o legado em `main.py` e o novo em `routers/`). Isso aumenta o risco de drift entre o que Flutter envia/espera e o que o backend processa. Recomenda-se:
1. Centralizar o contrato de resposta em schemas Pydantic com aliases (`Field(alias=...)`) para aceitar nomes alternativos
2. Adicionar testes de integração básicos que validem o contrato de resposta em campos críticos (study plan, quiz submit, ranking)

**Débito técnico acumulado — `_require_user()` duplicado:** A função `_require_user()` está copiada em `routers/user.py`, `routers/quiz.py` e `routers/flashcard.py` com implementação idêntica. Candidato a extração para `services.py` ou um módulo `auth_utils.py`.

**Deduplicação de questões (`QuizSeenQuestion`) funciona corretamente:** O sistema de fingerprint SHA-1 para evitar repetição de perguntas está bem implementado nos dois lados (backend e Flutter via parâmetros de geração). Nenhuma ação necessária.

**Simulado submit está correto:** Ao contrário do quiz, `simulado_result_screen.dart` envia corretamente `correct`, `total`, `accuracy`, `xp_earned` e `time_taken_seconds` via `simuladoRepositoryProvider.submitResult()`. O bug de stats ausentes era exclusivo do fluxo de quiz.

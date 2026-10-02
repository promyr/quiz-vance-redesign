# Roadmap: Smart Question Cache Pool (Reaproveitamento Inteligente Multi-Usuário)

## 1. Visão Geral e Regras de Negócio

Este módulo tem como objetivo otimizar drasticamente os custos de tokens com LLM (até 85% de redução) e entregar tempos de resposta quase instantâneos (< 100ms) ao transformar cada questão gerada em um ativo comunitário reaproveitável, respeitando a frescura cognitiva de cada usuário.

### Regras Centrais de Distribuição

1. **Prioridade Coletiva (Cross-User):**
   - Toda questão completa gerada por IA (enunciado, 4 alternativas, resposta correta, explicação, subtema, referências) é indexada no pool global.
   - Qualquer **outro usuário** que solicitar um quiz sobre o mesmo tópico/dificuldade recebe prioritariamente questões válidas do pool que ele ainda não tenha visto.

2. **Regra de Reciclagem para o Próprio Criador (Cooling Period de 100 Questões):**
   - Para o usuário que gerou a questão, o sistema **não** a repete imediatamente.
   - A questão só volta a ser elegível para o mesmo usuário se:
     - **Critério A (Esgotamento):** O pool não tiver questões inéditas suficientes para compor a quantidade solicitada E a cota de geração via IA estiver indisponível/esgotada; **OU**
     - **Critério B (Ciclo de 100 Questões):** O usuário já tiver respondido ou gerado pelo menos **100 perguntas diferentes** desse mesmo tópico desde que viu essa questão pela última vez (janela de resfriamento cognitivo).

---

## 2. Modelagem de Dados Recomendada

```python
class QuizCachedQuestionPool(Base):
    """Pool global de questões completas compartilhadas."""
    __tablename__ = "quiz_cached_question_pool"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    topic_key: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    difficulty: Mapped[str] = mapped_column(String(30), default="intermediario", index=True)
    fingerprint: Mapped[str] = mapped_column(String(32), nullable=False, unique=True)
    
    # Payload completo em JSON (compatível com QuestionModel no Flutter)
    payload_json: Mapped[dict] = mapped_column(JSON, nullable=False)
    
    # Metadados de qualidade e autoria
    created_by_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    times_served: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)


class QuizUserQuestionHistory(Base):
    """Rastreamento de exposição individual para cálculo da janela de 100 questões."""
    __tablename__ = "quiz_user_question_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    topic_key: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    cached_question_id: Mapped[int] = mapped_column(ForeignKey("quiz_cached_question_pool.id", ondelete="CASCADE"), nullable=False)
    
    # Número sequencial da questão que o usuário fez nesse tópico (contador incremental)
    seen_at_seq: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("ix_user_topic_seq", "user_id", "topic_key", "seen_at_seq"),
    )
```

---

## 3. Algoritmo de Seleção

```
Ao solicitar N questões para (user_id, topic, difficulty):
  1. Obter seq_atual = contagem de questões que user_id já fez no tópico.
  2. Buscar questões do pool onde topic_key == topic e difficulty == difficulty:
     - EXCLUIR se question_id foi vista por user_id onde (seq_atual - seen_at_seq) < 100.
     - Se question.created_by_user_id == user_id, prioridade menor (usar apenas se faltar candidatos de outros autores).
  3. Se quantidade encontrada >= N:
     - Embaralhar candidatos válidos.
     - Selecionar N questões.
     - Registrar no histórico (seen_at_seq = seq_atual + i).
     - Retornar imediatamente (< 50ms, 0 tokens).
  4. Se quantidade encontrada < N:
     - Usar as encontradas (ou chamar IA para gerar o delta faltante).
     - Persistir as novas questões geradas no pool global.
```

---

## 4. Prompt de Execução Pronta para Uso Futuro

> **Instrução para o Agente:** Quando o usuário solicitar *"implemente o pool de cache do roadmap"*, execute o prompt abaixo na íntegra:

```markdown
Você é o engenheiro responsável pela implementação do Smart Question Cache Pool do Quiz Vance.

OBJETIVO:
Implementar o sistema de cache semântico coletivo e ciclo de reutilização de 100 questões conforme documentado em docs/ROADMAP_SMART_CACHE_POOL.md.

TAREFAS:
1. Criar as tabelas QuizCachedQuestionPool e QuizUserQuestionHistory em backend/app/models.py com os índices adequados.
2. Em backend/app/smart_cache_service.py:
   - Implementar store_questions(db, topic, difficulty, questions, created_by_user_id) persistindo o payload completo com alternativas e gabarito em JSON.
   - Implementar get_candidate_questions(db, user_id, topic, difficulty, quantity):
     * Priorizar questões onde created_by_user_id != user_id.
     * Permitir questões de created_by_user_id apenas se (seq_atual - seen_at_seq) >= 100 ou se o pool de terceiros estiver esgotado.
     * Retornar objetos completos compatíveis com o Question.fromJson do Flutter.
3. Em backend/app/routers/quiz.py:
   - Conectar o retorno do cache no endpoint /quiz/generate antes de acionar a LLM.
   - Registrar no histórico as questões servidas via cache e via LLM para manter o contador de sequência preciso.
4. Testes e Validação:
   - Criar backend/tests/test_smart_cache_pool.py cobrindo:
     * Usuário A gera questão -> Usuário B recebe a questão do pool sem chamar IA.
     * Usuário A não recebe sua própria questão antes de completar 100 questões do mesmo tópico.
     * Usuário A recebe a questão de volta após atingir o ciclo de 100 questões ou por esgotamento total.
   - Garantir que a suíte completa de testes do backend e flutter analyze permaneçam 100% verdes.
```

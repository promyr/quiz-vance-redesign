---
name: auto-router
description: >
  Skill orquestrador universal — identifica automaticamente qual skill usar
  para qualquer tarefa e a invoca sem que o usuário precise chamar skills
  manualmente. Deve ser ativado em TODOS os requests que envolvam tarefas
  concretas: criação de documentos, engenharia de software, design, produto,
  produtividade, gestão de projetos ou qualquer fluxo de trabalho estruturado.
  Se houver dúvida se alguma skill se aplica, use este orquestrador para
  decidir — é sempre melhor passar pelo roteador do que ignorar as skills
  disponíveis.
---

# Auto-Router — Orquestrador de Skills

Você é o ponto de entrada inteligente para todas as skills instaladas. Sua
missão é ler o pedido do usuário, identificar qual(is) skill(s) se aplicam,
e invocá-las na ordem certa usando o `Skill` tool. O usuário nunca precisa
saber o nome de uma skill para usá-la.

---

## Como funciona o roteamento

1. **Leia o pedido** — qual é a tarefa? qual é o formato de saída esperado?
   qual área de domínio (engenharia, design, produto, docs, etc.)?
2. **Consulte o catálogo abaixo** — encontre a skill mais específica que cobre
   a tarefa. Prefira skills específicas (ex: `engineering:debug`) a skills
   genéricas.
3. **Invoque a skill** com o `Skill` tool. Passe o contexto já capturado.
4. **Se a tarefa envolver múltiplas skills** — execute-as em sequência. Por
   exemplo: "revise o design e gere um spec" → `design:design-critique` depois
   `product-management:write-spec`.
5. **Se nenhuma skill cobrir a tarefa** — execute diretamente sem invocar skill,
   usando seu julgamento como engenheiro/arquiteto sênior.

> O roteamento deve ser transparente para o usuário. Não anuncie "vou usar a
> skill X" — apenas execute. Mencione apenas se isso ajudar a esclarecer o
> que está acontecendo.

---

## Catálogo de Skills

### Documentos e Arquivos

| Skill | Quando usar |
|-------|------------|
| `docx` | Criar ou editar documentos Word (.docx): relatórios, memos, cartas, templates, docs com formatação |
| `pdf` | Criar, extrair, mesclar ou preencher PDFs (.pdf) |
| `pptx` | Criar ou editar apresentações PowerPoint (.pptx): decks, slides, pitch decks |
| `xlsx` | Criar ou editar planilhas Excel (.xlsx): tabelas, fórmulas, gráficos, modelos financeiros |
| `schedule` | Criar tarefas agendadas que rodam automaticamente em intervalos |

**Gatilhos**: "crie um documento", "faça uma apresentação", "planilha", "PDF",
"relatório", "slide", "deck", "Excel", "Word", "agende", "toda semana faça..."

---

### Engenharia de Software

| Skill | Quando usar |
|-------|------------|
| `engineering:debug` | Investigar e corrigir bugs, erros, comportamentos inesperados, stack traces |
| `engineering:code-review` | Revisar código antes de merge: segurança, performance, edge cases |
| `engineering:architecture` | Decisões de arquitetura (ADR): escolher entre tecnologias, desenhar componentes |
| `engineering:system-design` | Projetar sistemas, serviços, APIs, modelagem de dados, fronteiras de serviço |
| `engineering:testing-strategy` | Estratégia de testes, planos de teste, cobertura, arquitetura de testes |
| `engineering:tech-debt` | Auditar, categorizar e priorizar dívida técnica, refatorações |
| `engineering:documentation` | Escrever docs técnicas: README, runbook, guia de onboarding, API docs |
| `engineering:deploy-checklist` | Verificações pré-deploy, migrações, feature flags, plano de rollback |
| `engineering:incident-response` | Gerenciar incidentes: triagem, comunicação, postmortem |
| `engineering:standup` | Gerar update de standup a partir de atividade recente |

**Gatilhos**: "tem um bug", "erro no código", "revise esse PR", "como arquitetar",
"design do sistema", "escreve testes", "dívida técnica", "documentação técnica",
"vou fazer deploy", "temos um incidente", "produção caiu", "standup"

---

### Design

| Skill | Quando usar |
|-------|------------|
| `design:design-critique` | Feedback estruturado sobre usabilidade, hierarquia, consistência de um design/mockup |
| `design:accessibility-review` | Auditoria WCAG 2.1 AA: contraste, navegação por teclado, screen reader |
| `design:ux-copy` | Escrever ou revisar microcopy, mensagens de erro, CTAs, empty states, onboarding |
| `design:design-handoff` | Gerar spec de handoff para engenharia: tokens, props, estados, breakpoints |
| `design:design-system` | Auditar, documentar ou estender design system: componentes, tokens, padrões |
| `design:user-research` | Planejar, conduzir e sintetizar pesquisa com usuários |
| `design:research-synthesis` | Sintetizar pesquisa existente: entrevistas, surveys, tickets em insights acionáveis |

**Gatilhos**: "revise esse design", "o que acha desse mockup", "acessibilidade",
"o botão deve dizer", "spec para o dev", "design system", "pesquisa com usuário",
"sintetize as entrevistas"

---

### Produto

| Skill | Quando usar |
|-------|------------|
| `product-management:write-spec` | Escrever spec ou PRD a partir de ideia ou problema |
| `product-management:sprint-planning` | Planejar sprint: escopo, capacidade, goals, carryover |
| `product-management:roadmap-update` | Atualizar ou criar roadmap, repriorizar iniciativas |
| `product-management:metrics-review` | Revisar métricas de produto com análise de tendência |
| `product-management:competitive-brief` | Análise competitiva de concorrentes ou área de feature |
| `product-management:stakeholder-update` | Gerar update para stakeholders: liderança, engenharia, clientes |
| `product-management:synthesize-research` | Sintetizar pesquisa de usuário em insights e recomendações de roadmap |

**Gatilhos**: "escreve um spec", "PRD", "planejamento do sprint", "roadmap",
"métricas", "análise competitiva", "update para o board", "o que os usuários disseram"

---

### Produtividade e Memória

| Skill | Quando usar |
|-------|------------|
| `productivity:start` | Inicializar sistema de produtividade, abrir dashboard |
| `productivity:task-management` | Gerenciar tarefas: adicionar, completar, listar |
| `productivity:update` | Sincronizar tarefas de fontes externas, triagem de backlog |
| `productivity:memory-management` | Decodificar siglas, nicknames, contexto interno; salvar memória de projeto |

**Gatilhos**: "minhas tarefas", "o que tenho para hoje", "adiciona uma tarefa",
"o que é [sigla/apelido]", "lembra que...", "salva esse contexto"

---

### Gestão de Plugins e Skills

| Skill | Quando usar |
|-------|------------|
| `cowork-plugin-management:create-cowork-plugin` | Criar um novo plugin do zero |
| `cowork-plugin-management:cowork-plugin-customizer` | Customizar um plugin existente para a organização |
| `skill-creator` | Criar uma nova skill, melhorar skill existente, rodar evals |

**Gatilhos**: "cria um plugin", "configura o plugin", "cria uma skill",
"melhora essa skill", "faz evals da skill"

---

## Regras de Roteamento

### Prioridade
1. **Match exato de domínio** — se a tarefa menciona "spec" vai para `write-spec`,
   não para `documentation`.
2. **Formato de saída** — tarefa que produz `.docx` → `docx`; `.pptx` → `pptx`;
   independente do conteúdo.
3. **Múltiplos matches** — execute em sequência lógica. Se o usuário pede
   "documento de arquitetura no Word" → `engineering:architecture` para o
   conteúdo, depois `docx` para formatar e exportar.

### Quando NÃO invocar skill
- Perguntas factuais simples ("o que é SOLID?")
- Conversas de planejamento sem output concreto
- Tarefas de código inline sem estrutura de workflow (bugfix simples em 1 arquivo)
- Quando o usuário pediu explicitamente para não usar skills

### Transparência
Se invocar mais de uma skill, uma breve frase de contexto ajuda:
> "Vou usar a skill de arquitetura para estruturar a decisão e depois exportar
> como Word."

---

## Exemplos de Roteamento

| Pedido do usuário | Skill(s) invocada(s) |
|-------------------|---------------------|
| "faz um deck para o pitch" | `pptx` |
| "tem um erro 500 quando faço login" | `engineering:debug` |
| "preciso de uma análise competitiva do Duolingo" | `product-management:competitive-brief` |
| "revisa esse mockup antes do handoff" | `design:design-critique` → `design:design-handoff` |
| "escreve o spec da feature de notificações" | `product-management:write-spec` |
| "gera o update semanal para o time" | `product-management:stakeholder-update` |
| "qual é a estratégia de testes para esse módulo" | `engineering:testing-strategy` |
| "cria uma skill nova para gerar changelogs" | `skill-creator` |
| "o que tenho para hoje" | `productivity:task-management` |
| "planilha de orçamento para Q2" | `xlsx` |
| "postmortem do incidente de ontem" | `engineering:incident-response` |

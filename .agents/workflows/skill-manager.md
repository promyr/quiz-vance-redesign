---
description: Avalia o contexto atual do projeto, conversa e requisição para acionar as Skills globais mais relevantes automaticamente.
---

# Skill Manager (Orquestrador de Habilidades)

Este workflow funciona como uma "função de gerenciamento" e instrui o assistente (Antigravity) a agir como um roteador de skills inteligente. Ele deve ser adotado **sempre** antes de iniciar uma nova tarefa complexa no projeto.

## 1. Leitura de Contexto (Context Parsing)
Antes de modificar arquivos, analisar:
- **O pedido do usuário**: Qual é a intenção principal? (ex: SEO, Acessibilidade, UI Design, Otimização de Performance, Banco de Dados).
- **A Stack Tecnológica**: Ler os principais arquivos do projeto (ex: `package.json`, `.csproj`, `BUILD_APK.ps1`, `pubspec.yaml`, frameworks ativos).
- **A Conversa Anterior**: O que estava sendo discutido ou qual era a prioridade do momento.

## 2. Seleção de Skills Especializadas
O assistente *sempre* tem acesso à lista completa de skills disponíveis localmente no sistema. 
- Com base na Leitura de Contexto, selecione **até 3 skills especializadas** que mais se adequam à tarefa atual.
- Mantenha na memória as "Skills Ativas por Padrão" (como `tdd-workflow`, `clean-code`, `lint-and-validate`) que operam silenciosamente em background.
- Em caso de tecnologias muito específicas (ex: React, Flutter, Python, SQL), priorize a leitura primária da respectiva skill.

## 3. Acionamento (Activation)
Para cada skill especializada selecionada no Passo 2:
- Utilize a ferramenta de visualizar arquivo (`view_file`) no manifesto local da skill escolhida (ex: `C:\Users\Belchior\.gemini\antigravity\skills\[nome-da-skill]\SKILL.md`).
- Leia atentamente as diretrizes daquela skill.

## 4. Orquestração e Síntese
Depois de processar as instruções das skills:
- Crie um breve sumário mental ou artefato unindo os requisitos da tarefa com as melhores práticas extraídas das skills.
- As skills especializadas devem **sobrescrever** comportamentos genéricos. Se a skill XYZ ditar que "O framework A precisa de testes com padrão B", isso se torna a regra absoluta para aquela sessão.

*Sempre siga essas etapas invisíveis antes de iniciar uma execução de grande impacto para garantir que as habilidades perfeitas para a ocasião sobressaiam!*

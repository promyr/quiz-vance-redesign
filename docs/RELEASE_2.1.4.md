# Quiz Vance 2.1.4 (Android build 76)

## Melhorias

- Resultados de quizzes e simulados são guardados na fila local antes do envio. A fila é processada após login, retorno ao app, reconexão e a cada minuto, com uma operação por conta. Falhas temporárias permanecem pendentes com intervalo entre tentativas. Itens rejeitados permanentemente ficam preservados em armazenamento de recuperação após cinco tentativas.
- Escritas simultâneas na fila não perdem entradas; reenvios usam o identificador da sessão. A troca de conta cancela requisições protegidas e conserva a fila da conta original. Estatísticas e histórico são atualizados após sincronização confirmada.
- Revisões de flashcards usam o contrato correto e a data do evento. Repetir uma revisão já aplicada, ou enviar uma mais antiga, não avança novamente o agendamento. Bloqueios de linha foram acrescentados para o banco de produção; concorrência real em PostgreSQL não foi exercitada localmente.
- “Sugestão de revisão” oferece questões erradas ainda não dominadas, priorizando o tema com mais erros. Inicia a revisão diretamente, sem alterar o plano. O caderno é recarregado na troca de conta.
- Na revisão do edital, é possível editar disciplinas e tópicos e adicionar uma disciplina. São conservados pesos e evidências da extração. As alterações alimentam a geração do plano; não constituem um rascunho persistente separado.
- A geração recebe uma distribuição equilibrada dos tópicos explícitos. Isso orienta o provedor de IA; não comprova que todas as respostas respeitarão integralmente a distribuição.
- O indicador de sincronização quebra o texto em telas estreitas e com fonte ampliada. A Biblioteca e a revisão do edital foram separadas em arquivos menores, preservando suas ações.
- Pipeline corrigido para validar o mapa de arquitetura rastreado e usar a versão pública sem o sufixo do build Android. Imports e avisos de validação do backend foram corrigidos.

## Validação

432 testes Flutter passaram, incluindo inicialização, fila concorrente, troca de conta, revisão de erros, edição do edital e layout a 320 pixels com escala de texto 1,6. Flutter analyze sem avisos. 210 testes do backend passaram. Ruff no diretório backend sem problemas. Bandit não encontrou problemas de severidade média ou alta; existem 15 apontamentos de severidade baixa preexistentes.

Os testes do backend usaram diretório temporário próprio porque o diretório padrão do Windows negava acesso. Permanecem dois avisos de operação OpenAPI duplicada em rotas GET/HEAD de download. Não houve teste em aparelho Android físico. A fila não retrodata estatísticas de resultados recebidos em outro dia; os resultados são contabilizados conforme o comportamento atual do servidor.

## Publicação

APK, assinatura, download público e entrega pelo bot serão registrados após confirmação.

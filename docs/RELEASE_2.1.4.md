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

Código e APK publicados no commit be341d2. Readiness público HTTP 200; versão 2.1.4. Download integral verificado: 40.564.378 bytes, SHA-256 A1FFEDEF3519E160A939C5884D7179E5E92527FED3C6FBB780E757A404CC42E4. Assinatura v2 com o certificado de produção preservado.

O GitHub aprovou higiene de segredos e testes/análise estática do backend. O build Docker revelou psycopg2-binary 2.9.10 sem wheel para Python 3.14; atualização para 2.9.13, com wheel oficial Linux verificado e 210 testes novamente aprovados. Referência: https://www.psycopg.org/docs/news.html. A etapa Android no GitHub está bloqueada pela ausência dos quatro secrets de assinatura; o APK entregue foi compilado e assinado localmente.


Entrega pelo Gerent3Bot confirmada no tópico Atualizações, mensagem 929: https://t.me/c/3742591996/929. Tamanho confirmado pelo Telegram igual ao APK verificado. Credencial fornecida por entrada oculta, sem gravação em arquivo.


## Complemento de segurança e rotação

O scan remoto confirmou vulnerabilidades em dependências e na imagem base. Atualizadas cryptography para 50.0.2, pypdf para 6.19.0 e python-multipart para 0.0.30; imagem Python 3.14.8 com upgrade dos pacotes Debian durante o build. Os limites do scan foram preservados. Fontes verificadas: https://www.python.org/downloads/release/python-3148/, https://cryptography.io/en/50.0.2/changelog/, https://pypdf.readthedocs.io/en/latest/meta/CHANGELOG.html.

Um teste intermitente de rotação foi reproduzido com relógio congelado: sucessos no mesmo instante podiam quebrar a alternância dos provedores. O registro de sucesso agora mantém timestamps estritamente crescentes em operações sequenciais. Essa correção não afirma serialização global entre transações concorrentes. O teste de regressão passou.

Validação final das dependências atualizadas: 211 testes do backend aprovados, Ruff sem problemas e pip check sem incompatibilidades. Os 432 testes Flutter continuam correspondendo ao APK já enviado, que não foi alterado por este complemento do backend.

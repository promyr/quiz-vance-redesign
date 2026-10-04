# Quiz Vance 2.1.3 (Android build 75)

## Comportamento acrescentado

- Quiz pode ser pausado e retomado com perguntas, alternativas selecionadas, respostas anteriores, posição e tempo acumulado. No plano, o mesmo item retoma automaticamente; na área de quizzes, há “Retomar quiz pausado”. Encerrar continua disponível e remove o checkpoint.
- O plano recarrega seu progresso ao retornar do quiz, mantém os indicadores de conclusão e oferece acesso direto à próxima sessão pendente.
- Texto extraído dos PDFs é reutilizado por conta: até três documentos, limite de um milhão de caracteres por documento, validade de 24 horas. Respostas vazias e falhas não são armazenadas. Reanálise e exclusão invalidam o texto salvo. Requisições simultâneas do mesmo documento compartilham a leitura.
- Trechos são classificados pelos termos da matéria e dos tópicos antes da sanitização, incluindo capítulos distantes do início. Não há busca semântica nem garantia de relevância perfeita.
- Repetir a geração conserva os parâmetros e o texto já preparado. Falhas do serviço, limite do provedor e limite de uso recebem mensagens específicas. A indisponibilidade do texto mantém o fallback existente pelos tópicos do plano.
- Diagnósticos locais registram duração, sucesso/falha e quantidade de repetições exatas de perguntas. Até 30 amostras e 200 hashes; não armazenam tópicos, textos das perguntas ou credenciais nas métricas. Não são enviados ao servidor nem alteram regras de geração.

## Persistência e limites

Checkpoints usam armazenamento local por conta, com fila de escrita, até oito sessões e validade de sete dias. Não são sincronizados entre aparelhos. Dados inválidos são ignorados; armazenamento indisponível não impede início do quiz. Os modos infinito e revisão e os IDs de plano/sessão são conservados. O cache coletivo de questões permanece no roadmap e não foi implementado nesta entrega.

## Validação

125 testes passaram nas áreas de plano, quiz, conteúdo e roteamento. A análise estática dos arquivos afetados passou sem problemas. Cobertura inclui retomada na tela, botão de recuperação, isolamento por conta, concorrência do cache, limpeza na conclusão, atualização visual do plano ao retornar e manutenção das estatísticas.

O teste de modularidade continua com uma falha preexistente: Library tem 1115 linhas contra limite de 1000. O arquivo não foi alterado nesta entrega. Os arquivos alterados respeitam os limites existentes.

A validação automatizada não substitui teste em aparelho Android físico; isso não foi realizado neste ambiente. Assinatura, tamanho, hash, download publicado e entrega pelo bot serão conferidos na publicação.

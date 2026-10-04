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

A validação automatizada não substitui teste em aparelho Android físico; isso não foi realizado neste ambiente. Assinatura v2 e identidade do certificado foram verificadas. O APK público foi baixado integralmente: 40.541.806 bytes, SHA-256 FC2E597D2344B5C118D333A7E0B28D419B18DB32A90EF2FC02EFAAF8F9C0B0C2. O backend respondeu readiness HTTP 200 com banco disponível e anunciou 2.1.3.

## Pipeline e publicação

Código/APK publicados no commit 34c0099. No GitHub, o job de higiene de segredos e a etapa de testes do backend passaram. O job do backend falhou em Ruff por oito problemas preexistentes de imports/variável não utilizados; a compilação Android e o scan de imagem dependentes foram pulados. O APK Android desta entrega foi compilado e validado localmente. Não se declara o pipeline geral aprovado.

Somente os arquivos revisados foram enviados pelo checkout isolado. Uma tentativa de commit no checkout principal incluiu arquivos não relacionados; seu push foi rejeitado por não ser fast-forward. O commit foi desfeito preservando todos os arquivos e uma branch local de recuperação. Nenhum desses arquivos não relacionados foi publicado nesta entrega.

Entrega pelo Gerent3Bot confirmada no tópico Atualizações, mensagem 927: https://t.me/c/3742591996/927. O tamanho devolvido pelo Telegram corresponde aos 40.541.806 bytes do APK verificado. A credencial foi fornecida por entrada oculta e não foi gravada em arquivo.

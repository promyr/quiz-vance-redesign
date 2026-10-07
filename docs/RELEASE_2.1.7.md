# Quiz Vance 2.1.7 — build 79

Revisões de flashcards recebidas fora de ordem mantêm créditos únicos e recompõem o agendamento cronologicamente. Reenvios não duplicam XP. Datas futuras acima da tolerância de cinco minutos são rejeitadas; sincronizar um estado antigo preserva o agendamento de cartões já revisados no servidor.

A geração de quiz verifica se o documento pertence à conta antes de consumir cota ou chamar a IA. A validação de questões de associação rejeita rótulos duplicados/brancos/nulos, referências inexistentes e premissas incompletas, reconhecendo tipo com acento e algarismos romanos Unicode.

A barra de progresso permite quebra de linha, e a navegação inferior acompanha a altura do conteúdo. Passaram 503 testes Flutter e a matriz de 24 combinações de largura/fonte/conta, incluindo os seis casos antes reprovados. Os 25 fixtures adicionais de associação passaram; regressões de revisão, migração e isolamento de documentos também passaram.

Migração `20261007_23`: acrescenta vínculo do cartão, grau e estado inicial ao histórico de revisões, preservando eventos e XP antigos. Atualização e reversão verificadas em banco isolado; a inicialização do backend aplica a migração. Créditos históricos já perdidos não são reconstruídos automaticamente.

APK universal com o certificado de produção existente. Download público e entrega pelo bot serão registrados nos recibos após confirmação. A geração de IA nos testes usa entradas determinísticas; não equivale à qualidade pedagógica de todas as respostas de provedores reais.

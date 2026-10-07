# Quiz Vance 2.1.7 — build 79

Revisões de flashcards recebidas fora de ordem mantêm créditos únicos e recompõem o agendamento cronologicamente. Reenvios não duplicam XP. Datas futuras acima da tolerância de cinco minutos são rejeitadas; sincronizar um estado antigo preserva o agendamento de cartões já revisados no servidor.

A geração de quiz verifica se o documento pertence à conta antes de consumir cota ou chamar a IA. A validação de questões de associação rejeita rótulos duplicados/brancos/nulos, referências inexistentes e premissas incompletas, reconhecendo tipo com acento e algarismos romanos Unicode.

A barra de progresso permite quebra de linha, e a navegação inferior acompanha a altura do conteúdo. Passaram 503 testes Flutter e a matriz de 24 combinações de largura/fonte/conta, incluindo os seis casos antes reprovados. Os 25 fixtures adicionais de associação passaram; regressões de revisão, migração e isolamento de documentos também passaram.

Migração `20261007_23`: acrescenta vínculo do cartão, grau e estado inicial ao histórico de revisões, preservando eventos e XP antigos. Atualização e reversão verificadas em banco isolado; a inicialização do backend aplica a migração. Créditos históricos já perdidos não são reconstruídos automaticamente.

APK universal com o certificado de produção existente. Download público e entrega pelo bot serão registrados nos recibos após confirmação. A geração de IA nos testes usa entradas determinísticas; não equivale à qualidade pedagógica de todas as respostas de provedores reais.

## Publicação confirmada

Backend atualizado, `/health/ready` com banco saudável e `/app/update` anunciando 2.1.7. Download público conferido com o artefato local assinado: 40.692.082 bytes, SHA-256 `2F2E7E3BE5355FACD901F1952376BC49BDD2BE14370EF973787F1900DB080526`.

APK: `output_apk/quiz-vance-2.1.7-universal.apk`; pacote `com.quizvance.quiz_vance_flutter`, versão 2.1.7, código 79. Certificado de produção: `CN=Quiz Vance, OU=Mobile, O=Quiz Vance, L=Sao Paulo, ST=Sao Paulo, C=BR`; SHA-256 `B039A11E96AAFA7107BE445BD6404516ADA37962C0B735C059939EA15CA67215`. Assinatura v2 e alinhamento 16 KB verificados.

Bot confirmou documento anexado no Telegram, mensagem 958: https://t.me/c/3742591996/6/958 . Recibo incorporado ao manifesto para preservar a confirmação e impedir publicação duplicada.

Validação: 503 testes Flutter anteriores, 260 testes locais da fonte sincronizada, Ruff e Bandit aprovados. CI do commit `360bc7d701765f17e3481b1ead471350cc0809e6`: higiene de segredos, backend, imagem, SBOM e scan aprovados. Job Android automático falhou pela ausência dos segredos de assinatura no GitHub; APK publicado foi gerado e assinado localmente.

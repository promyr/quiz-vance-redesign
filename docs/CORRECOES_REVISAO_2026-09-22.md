# Correções da revisão — 22/09/2026

Base: `REVISAO_ATUAL_2026-09-21.md`, versão de código 2.0.64+63.
Não houve build novo, deploy, alteração de banco de produção ou envio Telegram.
As alterações preexistentes da árvore de trabalho foram preservadas.

## Decisões

- Correções pontuais nos repositórios, providers e telas existentes; sem troca de arquitetura.
- Compatibilidade de leitura das chaves antigas, em vez de pedir novo cadastro de todas as chaves.
- Preservação da conta reconhecida e telas exclusivas de desbloqueio/outra conta.
- Exclusão da Biblioteca persistida por conta e instalação, sem apagar o PDF remoto compartilhado com o processamento.
- Render mantido como destino atual do projeto; não mudar silenciosamente usuários para a base antiga do Fly.
- Nenhuma contratação de disco/plano ou rotação de credencial sem acesso administrativo apropriado.

## Estado dos achados

| Achado | Correção local | Limite ou pendência |
| --- | --- | --- |
| R01 Token no script | Token retirado e publicador antigo desativado com erro explícito, sem envio | Revogar token no BotFather; cópias/histórico continuam potencialmente expostos |
| R02 Import ausente | `os` importado; caminhos de criptografia exercitados | Publicar backend corrigido |
| R03 Derivação incompatível | Leitura de v1 original e transitório; novas gravações v2 com salt junto ao ciphertext | Preservar chaves mestras anteriores e salt transitório configurado; não foi feita recriptografia em massa |
| R04 Conta biométrica divergente | Cofre anterior limpo no login por senha; identidade comparada antes do refresh e após resposta | Digital nativa ainda precisa ser testada em Android |
| R05 Não lembrar login | Cadastro biométrico exige lembrar; tokens do login sem persistência ficam em memória | Teste real de encerramento/reabertura no aparelho |
| R06 Plano legado | Migração escreve diretamente na persistência interna, sem recursão | Teste de atualização sobre instalação real antiga |
| R07 Edital pronto | Busca detalhe quando a listagem traz apenas resumo; protege resposta de seleção ultrapassada | Smoke com edital real no servidor |
| R08 Páginas excluídas | União de páginas relevantes e preservação da continuação do anexo; janelas de 8k mantidas | Pode analisar mais segmentos; pertinência semântica continua dependente do modelo e evidências |
| R09 Destinos/durabilidade | CI alinhado ao Render; scripts sem fallback silencioso para Fly | Render sem resposta; `/tmp` ainda não é armazenamento durável; provisionamento pendente |
| R10 Timeout sem retry | Timeouts e falhas transitórias reais do httpx classificados para retry | Disponibilidade/cota dos provedores não foi testada com credenciais |
| R11 Exclusão revertida | Tombstone persistente por conta; recuperação e importação respeitam exclusão, inclusive durante download | PDF remoto não é apagado; reinstalação/outro aparelho não compartilham tombstone; novo upload gera novo ID |
| R12 Sessão/fluxo/logout | Bootstrap restaura sessão; evita restauração duplicada; telas exclusivas; voltar limpa senha; logout limpa cofre | Não foi introduzida nova política temporal de bloqueio por inatividade; comportamento nativo/standby precisa de teste |
| R13 Sucesso falso | Publicador único no backend valida manifesto, hash de ambos APKs, arquivo, tamanho, grupo e tópico retornados | Não foi publicado; manifesto atual antigo deve ser substituído pelo de um novo build verificado |

## Criptografia e implantação

`enc:v1:` permanece legível com a derivação da migração original (salt vazio), com
a derivação transitória de salt padrão e com `DATA_ENCRYPTION_SALT` quando usado.
`DATA_ENCRYPTION_PREVIOUS_KEYS` continua permitindo leitura com chaves anteriores.
Não descartar os valores antigos antes de validar todos os registros.

As novas gravações são `enc:v2:<salt>:<token>`. O salt público é guardado junto ao
ciphertext; a chave mestra não é incorporada. Chamadas explícitas de criptografia
com v1 legível podem produzir v2, mas esta entrega não atualizou registros em massa.
Rollback para um backend sem leitor v2 não pode ler novas gravações v2: implantar
com backup e manter um rollback que contenha este leitor. A necessidade de guardar
o salt é descrita na [documentação de Fernet](https://cryptography.io/en/stable/fernet/).

## Pendências operacionais antes do teste mobile

1. Revogar no BotFather a credencial que esteve no Git e configurar a substituta
   exclusivamente no ambiente seguro do servidor. Não enviar o token em chat/commit.
2. Inspecionar logs/deploy/banco do Render. Em 22/09, GET público de
   `/health/ready` expirou em 20 segundos sem bytes; isso não determina sua causa.
3. Configurar armazenamento durável e verificar sobrevivência de PDFs após
   reinício/substituição de container. O blueprint atual usa `/tmp/study_documents`.
   O [Render Free não oferece discos persistentes](https://render.com/docs/free);
   escolher disco compatível em plano pago ou armazenamento externo antes do deploy.
   Nenhum plano pago foi contratado nem configuração privada alterada.
4. Validar sob Python/dependências da imagem de produção. Os testes locais usaram
   a `.venv` existente, que diverge de alguns pins de `requirements.txt`.
5. Gerar APK versionado pelos scripts oficiais e conferir assinatura/versão interna.
   Copiar o manifesto correspondente junto aos arquivos no diretório
   `backend/releases/android/` antes de montar a imagem que publicará o APK.
6. No servidor validado, usar `scripts/publish_telegram_release_link.py` com
   `RELEASE_VERSION` e o destino Atualizações configurado no banco. O publicador
   rejeita manifesto ausente/desatualizado; não fabricar um manifesto para o APK antigo.
7. Confirmar o anexo na mensagem retornada pelo Telegram e testar instalação limpa,
   atualização, troca de contas, digital, standby e PDF em segundo plano no Android.

## Validação

- Testes novos reproduziram antes das correções: criptografia, timeout/seleção de páginas,
  migração legada, reabertura de edital, recuperação de material excluído e autenticação.
- Backend: 156 testes aprovados; Ruff aprovado.
- Bandit: nenhum achado médio/alto; 12 achados baixos permanecem fora deste recorte.
- Detector de segredos: zero ocorrências na árvore verificada. Não equivale a revogar
  credenciais nem limpar o histórico do Git.
- Scripts PowerShell alterados: parsing sintático aprovado, sem executar publicação/build.
- Flutter: análise estática aprovada e 379 testes aprovados.

Esta entrega não comprova disponibilidade de produção, funcionamento nativo da digital,
qualidade integral do plano gerado pelo provedor nem distribuição efetiva pelo Telegram.

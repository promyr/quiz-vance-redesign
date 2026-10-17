# Correção da avaliação de qualidade

Base inspecionada: `825b646` em main, limpa no início desta rodada. A unificação
das fontes e a remoção de experimental/testes de flashcards já estavam nesse
commit. Nenhum reset, descarte de alterações ou remoção de worktree foi necessário.
Backup Git de todas as refs: `output/quality-remediation-2026-10-17/pre-change.bundle`
(local, ignorado, não publicar). Arquivos locais ignorados permanecem no lugar.

## Mudanças desta rodada

- Job Flutter de análise/testes independente da assinatura; release Android
  restrita a tags/manualmente e dependente dos checks de Flutter, backend e imagem.
- Contrato de CI com mutações negativas que detectam quatro formas de bypass.
- Guardas de fontes para os dois entrypoints de APK: erro Git, árvore suja,
  arquivo novo e mudança de commit bloqueiam a release. Testes em repositório
  temporário verificam os casos de recusa e aceitação.
- Versão completa e limite do versionCode no build geral; APP_VERSION inclui build.
- Verificação de codificação antes de empacotar. O manifesto local atual já tem
  UTF-8 correto; sua proveniência antiga não foi reescrita.
- Tratamento de falha síncrona/assíncrona do reporter de erros, descarte de
  consultas antigas de edital, prevenção de polling sobreposto e guardas de
  ciclo de vida no login/admin/picker de PDF, com regressões.
- Política de release alinhada ao Docker/Render atual, sem mudar o processo de migration.

## Segurança e validação

O usuário informou ter revogado o token antigo. Ainda falta cadastrar o novo
somente em `TELEGRAM_BOT_TOKEN` no Render e validar o bot; não registrar tokens
em conversa, código, histórico ou relatórios. A inspeção delimitada dos scripts
Python/PowerShell de scratch não encontrou tokens de bot remanescentes.

As verificações locais de versão, CI, fonte limpa e codificação passaram.
O PC estava com aproximadamente 1,2 GB livres; por solicitação do usuário,
testes pesados não devem executar localmente. Flutter/backend e scanners serão
validados no GitHub Actions. Não foi gerado nem anunciado um novo APK nesta rodada.

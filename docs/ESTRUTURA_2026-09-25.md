# Continuidade estrutural — 25/09/2026

## Escopo e decisões

Continuação incremental do plano aprovado, preservando alterações preexistentes.
Sem deploy, publicação, mudança de banco ou geração de APK nesta etapa.
Não substituir infraestrutura nem remover o mecanismo de migração sem validar
como o ambiente atual executará essa etapa.

## Correções verificadas

- Armazenamento: cancelamento limpa uploads parciais; chaves de arquivo inválidas
  são rejeitadas; falhas de criação e leitura do disco recebem erro seguro 503.
  A extração já converte erros desse contrato em falha passível de retentativa.
- Upload: teste HTTP confirma que indisponibilidade de armazenamento não cria
  documento/job e não expõe o caminho privado na resposta.
- Seleção de cargo: repetir o cargo de um job queued/running/retrying preserva
  job, progresso, checkpoint e trava; selecionar outro cargo nesse intervalo
  retorna 409. Consulta do documento usa trava de linha para serializar seleção.
- Release: ambos os scripts PowerShell passam build-name/build-number alinhados
  à versão Dart e ao artefato. Versão ausente/inválida falha explicitamente;
  não há fallback para local.properties ou 1.0.0. O script geral aceita override.
- CI: manifesto inclui tamanho real do APK. Teste executa o comando JavaScript
  do workflow contra um arquivo de teste; não equivale a executar o build Android.

## Validação

- Backend: 172 testes aprovados na suíte completa com SQLite em memória.
- Após simplificação final do controle de fluxo: 13 testes da API de documentos
  novamente aprovados; Ruff aprovado.
- Flutter analyze: sem problemas.
- Flutter: 379 testes aprovados na suíte completa.
- Testes PowerShell de versão: aprovados sem executar build.
- Bandit: nenhum achado médio/alto; 12 baixos preexistentes permanecem.
- Detector de segredos: zero ocorrências na árvore analisada. Não verifica
  revogação de credenciais nem torna seguro o histórico do Git.

## Pendências e limites

1. Política de release falha: Dockerfile ainda executa `alembic upgrade head`
   em todo startup. Definir e validar etapa única de migração compatível com o
   ambiente Render antes de remover essa execução. Não enfraquecer o teste.
2. Armazenamento durável: `/tmp` continua não durável; tratamento de erros não
   substitui volume persistente ou object storage.
3. Acesso/logs/deploy do Render, disponibilidade real de login e provedores
   continuam não comprovados nesta etapa.
4. Trava concorrente depende do banco de produção; SQLite não comprova a
   serialização PostgreSQL sob múltiplos workers. Não há migração de esquema.
5. Validar imagem com versões de Python/dependências de produção; a venv local
   usa Python 3.12, diferente da imagem.
6. Revogar credencial Telegram anteriormente exposta, validar Android nativo,
   gerar/verificar novo APK e só depois realizar publicação controlada.

Os testes automatizados não comprovam login real, biometria nativa, qualidade
semântica do edital nem disponibilidade operacional do servidor.

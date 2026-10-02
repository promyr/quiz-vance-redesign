# Mitigação de cold start do backend

## Contexto e objetivo

- O backend gratuito do Render pode adormecer após inatividade.
- O tempo observado para voltar a responder foi de aproximadamente 56 segundos.
- O aplicativo deve iniciar normalmente, antecipar o despertar do backend e não
  transformar uma indisponibilidade temporária em falha ou travamento local.
- O fluxo atende Android e demais plataformas sem armazenar novos dados.

## Decisões

1. Executar `GET /health/ready` de forma assíncrona assim que o processo do app
   inicia e sempre que ele retorna ao primeiro plano.
2. Deduplicar chamadas simultâneas, sem criar monitoramento ou ping periódico.
3. Conter falhas do aquecimento; a operação solicitada pelo usuário continua
   responsável por confirmar sucesso ou apresentar erro.
4. Manter 75 segundos para autenticação por senha e biometria, cobrindo o cold
   start observado.
5. Após 800 ms de autenticação, mostrar `Conectando ao servidor...` como região
   acessível, removendo a mensagem assim que a operação termina.

## Alternativas descartadas

- Ping periódico: consome continuamente a franquia gratuita e não oferece uma
  garantia operacional confiável.
- Bloquear o bootstrap aguardando o health check: aumentaria o tempo para abrir
  o aplicativo e faria a disponibilidade do backend controlar toda a interface.
- Reduzir apenas o timeout: evita a falha precoce, mas desperdiça o tempo em que
  o usuário ainda está chegando à tela de autenticação.

## Critérios de validação

- chamadas simultâneas de aquecimento resultam em uma única requisição;
- falha no health check não impede o aplicativo de abrir;
- retorno do standby dispara novo aquecimento;
- login demorado informa o estado de conexão;
- análise estática e suíte Flutter completa permanecem verdes.

# Retired: this entrypoint embedded a bot credential and announced unchecked
# uploads as successful. Do not reintroduce local tokens or hardcoded topics.
$ErrorActionPreference = "Stop"
throw @"
Publicador antigo desativado por seguranca. Use o publicador validado no backend:
python scripts/publish_telegram_release_link.py
Configure RELEASE_VERSION e o destino Atualizacoes no ambiente seguro do servidor.
O token anteriormente exposto precisa ser revogado pelo administrador do bot.
Nenhum APK foi enviado por este script.
"@

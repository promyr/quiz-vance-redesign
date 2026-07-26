[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Error @"
Este helper foi desativado porque segredos nunca devem ser impressos no terminal.
Confirme apenas a presença de TELEGRAM_BOT_TOKEN com 'flyctl secrets list' e
faça a rotação diretamente no BotFather/Fly.
"@

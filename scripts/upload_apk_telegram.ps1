$pyScript = Join-Path $PSScriptRoot "upload_apk_telegram.py"
Write-Host "Executando upload via script Python (UTF-8)..." -ForegroundColor Cyan
python $pyScript

$mainPath = Join-Path $PSScriptRoot 'app\main.py'
$source = Get-Content -Raw -LiteralPath $mainPath
$expectedDecorator = '@app.api_route("/app/download/android/latest.apk", methods=["GET", "HEAD"])'

if (-not $source.Contains($expectedDecorator)) {
    throw 'A rota latest.apk ainda nao aceita GET e HEAD.'
}

Write-Output 'PASS: latest.apk aceita GET e HEAD.'

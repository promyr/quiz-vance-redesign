$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$activityPath = Join-Path $projectRoot 'android\app\src\main\kotlin\com\quizvance\quiz_vance_flutter\MainActivity.kt'
$localPropertiesPath = Join-Path $projectRoot 'android\local.properties'

if (-not (Test-Path -LiteralPath $activityPath)) {
    throw 'MainActivity.kt ausente: o APK instala, mas nao consegue iniciar.'
}

$activitySource = Get-Content -Raw -LiteralPath $activityPath
if (-not $activitySource.Contains('package com.quizvance.quiz_vance_flutter')) {
    throw 'O pacote da MainActivity nao corresponde ao applicationId.'
}
if (-not $activitySource.Contains('class MainActivity : FlutterActivity()')) {
    throw 'MainActivity nao herda de FlutterActivity.'
}

$localProperties = Get-Content -Raw -LiteralPath $localPropertiesPath
if (-not $localProperties.Contains('flutter.versionName=2.0.14')) {
    throw 'A versao Android deve ser 2.0.14.'
}
if (-not $localProperties.Contains('flutter.versionCode=8')) {
    throw 'O versionCode Android deve ser 8.'
}

Write-Output 'PASS: entrypoint Android e versao de reparo estao corretos.'

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$activityPath = Join-Path $projectRoot 'android\app\src\main\kotlin\com\quizvance\quiz_vance_flutter\MainActivity.kt'
$localPropertiesPath = Join-Path $projectRoot 'android\local.properties'
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$appConfigPath = Join-Path $projectRoot 'lib\core\config\app_config.dart'

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
$pubspec = Get-Content -Raw -LiteralPath $pubspecPath
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9A-Za-z._-]+)\+(\d+)\s*$')
if (-not $versionMatch.Success) {
    throw 'A versão canônica deve existir no pubspec.yaml.'
}
$versionName = $versionMatch.Groups[1].Value
$versionCode = $versionMatch.Groups[2].Value
$fullVersion = "$versionName+$versionCode"
if (-not $localProperties.Contains("flutter.versionName=$versionName")) {
    throw 'versionName Android diverge do pubspec.yaml.'
}
if (-not $localProperties.Contains("flutter.versionCode=$versionCode")) {
    throw 'versionCode Android diverge do pubspec.yaml.'
}
$appConfig = Get-Content -Raw -LiteralPath $appConfigPath
if (-not $appConfig.Contains("defaultValue: '$fullVersion'")) {
    throw 'APP_VERSION padrão diverge da versão canônica completa.'
}

Write-Output 'PASS: entrypoint Android e versão canônica estão corretos.'

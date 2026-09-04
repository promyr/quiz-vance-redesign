param(
    [ValidateSet("1", "2", "4", "all")]
    [string]$Palette = "all",
    [string]$BackendUrl = ""
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendConfigFile = Join-Path $ProjectDir "backend_url.txt"
$OutputDir = Join-Path $ProjectDir "output_apk"
$LocalPropertiesFile = Join-Path $ProjectDir "android\local.properties"
$PubspecFile = Join-Path $ProjectDir "pubspec.yaml"

function Get-LocalProperty {
    param([string]$Key)

    if (-not (Test-Path $LocalPropertiesFile)) {
        return $null
    }

    $line = Get-Content $LocalPropertiesFile |
        Where-Object { $_ -like "$Key=*" } |
        Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -replace '^[^=]+=','').Trim()
}

function Resolve-BackendUrl {
    param([string]$CliValue)

    if ($CliValue -and $CliValue.Trim()) {
        return $CliValue.Trim()
    }

    if ($env:QUIZ_VANCE_BACKEND_URL -and $env:QUIZ_VANCE_BACKEND_URL.Trim()) {
        return $env:QUIZ_VANCE_BACKEND_URL.Trim()
    }

    if (Test-Path $BackendConfigFile) {
        $configuredUrl = Get-Content $BackendConfigFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") } |
            Select-Object -First 1
        if ($configuredUrl) {
            return $configuredUrl
        }
    }

    return "https://quiz-vance-redesign-backend.fly.dev"
}

$BackendUrl = Resolve-BackendUrl -CliValue $BackendUrl

function Resolve-FlutterPath {
    $candidates = @(
        "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter.bat",
        "C:\src\flutter\bin\flutter.bat"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        return $flutterCommand.Source
    }

    throw "Flutter nao encontrado."
}

function Resolve-AppVersion {
    $localVersion = Get-LocalProperty "flutter.versionName"
    if ($localVersion) {
        return $localVersion
    }

    $match = Select-String -Path $PubspecFile -Pattern '^version:\s*([0-9A-Za-z.\-_]+)(?:\+\d+)?\s*$' | Select-Object -First 1
    if ($match) {
        return $match.Matches[0].Groups[1].Value.Trim()
    }

    return "1.0.0"
}

function Get-FlavorInfo {
    param([string]$PaletteId)

    switch ($PaletteId) {
        "1" {
            return @{
                flavor = "experimental1"
                theme = "1"
                label = "Quiz Vance Cor 1"
                output = "app-experimental1-universal-release.apk"
            }
        }
        "2" {
            return @{
                flavor = "experimental2"
                theme = "2"
                label = "Quiz Vance Cor 2"
                output = "app-experimental2-universal-release.apk"
            }
        }
        "4" {
            return @{
                flavor = "experimental4"
                theme = "4"
                label = "Quiz Vance Cor 4"
                output = "app-experimental4-universal-release.apk"
            }
        }
        default {
            throw "Paleta invalida: $PaletteId"
        }
    }
}

function Build-Flavor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PaletteId,
        [Parameter(Mandatory = $true)]
        [string]$Flutter,
        [Parameter(Mandatory = $true)]
        [string]$AppVersion
    )

    $info = Get-FlavorInfo -PaletteId $PaletteId
    $sourceApk = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-$($info.flavor)-release.apk"
    $targetApk = Join-Path $OutputDir $info.output

    Write-Host ""
    Write-Host "==> Building palette $PaletteId ($($info.label))" -ForegroundColor Cyan
    & $Flutter build apk --release --flavor $($info.flavor) -t lib\experimental\main_experimental.dart --no-pub "--dart-define=BACKEND_URL=$BackendUrl" "--dart-define=APP_VERSION=$AppVersion" "--dart-define=EXPERIMENT_THEME=$($info.theme)"
    if ($LASTEXITCODE -ne 0) {
        throw "Build falhou para a paleta $PaletteId."
    }

    if (-not (Test-Path $sourceApk)) {
        throw "APK esperado nao encontrado: $sourceApk"
    }

    Copy-Item $sourceApk $targetApk -Force
    Write-Host "    APK: $targetApk" -ForegroundColor Green
}

$Flutter = Resolve-FlutterPath
$AppVersion = Resolve-AppVersion

Set-Location $ProjectDir
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "Quiz Vance experimental build" -ForegroundColor Magenta
Write-Host "Flutter: $Flutter" -ForegroundColor DarkGray
Write-Host "Versao: $AppVersion" -ForegroundColor DarkGray

$palettes = if ($Palette -eq "all") { @("1", "2", "4") } else { @($Palette) }
foreach ($paletteId in $palettes) {
    Build-Flavor -PaletteId $paletteId -Flutter $Flutter -AppVersion $AppVersion
}

Write-Host ""
Write-Host "Builds prontos em: $OutputDir" -ForegroundColor Green

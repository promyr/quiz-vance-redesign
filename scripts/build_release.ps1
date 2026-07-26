param(
    [ValidateSet("android")]
    [string]$Platform = "android",
    [string]$BackendUrl = "",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$BackendConfigFile = Join-Path $ProjectDir "backend_url.txt"
$PackageConfig = Join-Path $ProjectDir ".dart_tool\package_config.json"
$PubspecLock = Join-Path $ProjectDir "pubspec.lock"
$LocalPropertiesFile = Join-Path $ProjectDir "android\local.properties"
$PubspecFile = Join-Path $ProjectDir "pubspec.yaml"
Set-Location $ProjectDir

function Write-Step([string]$Message) {
    Write-Host "`n> $Message" -ForegroundColor Cyan
}

function Write-OK([string]$Message) {
    Write-Host "  OK $Message" -ForegroundColor Green
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

function Resolve-FlutterCommand {
    $candidates = @(
        "C:\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter",
        "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter.bat",
        "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter"
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

    return $null
}

function Use-FlutterToolchain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FlutterCommand
    )

    $flutterBin = Split-Path -Parent $FlutterCommand
    $env:PATH = "$flutterBin;$env:PATH"
}

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $script:FlutterCmd @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Comando flutter falhou: flutter $($Arguments -join ' ')"
    }
}

function Ensure-Dependencies {
    if ((Test-Path $PubspecLock) -and (Test-Path $PackageConfig)) {
        Write-OK "Dependencias ja preparadas. Build seguira com --no-pub."
        return
    }

    Write-Step "flutter pub get --offline"
    try {
        Invoke-Flutter -Arguments @("pub", "get", "--offline")
        return
    } catch {
        Write-Host "  Cache offline insuficiente. Tentando pub get online..." -ForegroundColor Yellow
    }

    Write-Step "flutter pub get"
    Invoke-Flutter -Arguments @("pub", "get")
}

function Get-LocalProperty([string]$Key) {
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

function Resolve-AppVersion {
    if ($Version) {
        return $Version.Trim()
    }

    if (Test-Path $PubspecFile) {
        $match = Select-String -Path $PubspecFile -Pattern '^version:\s*([0-9A-Za-z.\-_]+\+\d+)\s*$' | Select-Object -First 1
        if ($match) {
            return $match.Matches[0].Groups[1].Value.Trim()
        }
    }

    $localVersion = Get-LocalProperty "flutter.versionName"
    $localCode = Get-LocalProperty "flutter.versionCode"
    if ($localVersion -and $localCode) {
        return "$localVersion+$localCode"
    }

    return "1.0.0"
}

$BackendUrl = Resolve-BackendUrl -CliValue $BackendUrl
$resolvedVersion = Resolve-AppVersion
$dartDefines = @(
    "--dart-define=BACKEND_URL=$BackendUrl",
    "--dart-define=APP_VERSION=$resolvedVersion"
)
$script:FlutterCmd = Resolve-FlutterCommand
if (-not $script:FlutterCmd) {
    throw "Flutter nao encontrado."
}
Use-FlutterToolchain -FlutterCommand $script:FlutterCmd

Write-Step "Quiz Vance release build - platform: $Platform"
Write-Host "  Backend URL: $BackendUrl" -ForegroundColor Gray
Write-Host "  Version: $resolvedVersion" -ForegroundColor Gray
Write-Host "  Flutter SDK: $script:FlutterCmd" -ForegroundColor Gray

Ensure-Dependencies

if ($Platform -eq "android") {
    Write-Step "Build Android APK"
    Invoke-Flutter -Arguments (@(
        "build", "apk", "--release", "--flavor", "production",
        "--target", "lib/main.dart", "--no-pub"
    ) + $dartDefines)
    $sourceApk = Join-Path $ProjectDir "build\\app\\outputs\\flutter-apk\\app-production-release.apk"
    $outputDir = Join-Path $ProjectDir "output_apk"
    $targetApk = Join-Path $outputDir "quiz-vance-$resolvedVersion-universal.apk"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
    $androidSdk = (Get-LocalProperty "sdk.dir") -replace '\\\\','\'
    $buildTools = Get-ChildItem -Directory (Join-Path $androidSdk "build-tools") |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $buildTools) {
        throw "Android build-tools nao encontrado."
    }
    $zipalign = Join-Path $buildTools.FullName "zipalign.exe"
    $apksigner = Join-Path $buildTools.FullName "apksigner.bat"
    & $zipalign -c -P 16 4 $targetApk
    if ($LASTEXITCODE -ne 0) {
        throw "APK de producao nao esta alinhado."
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $signatureReport = & $apksigner verify --verbose --print-certs $targetApk 2>&1
    $signatureExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($signatureExitCode -ne 0) {
        throw "Assinatura do APK de producao invalida."
    }
    $certificateLine = $signatureReport |
        Select-String "Signer #1 certificate SHA-256 digest:" |
        Select-Object -First 1
    if (-not $certificateLine) {
        throw "Digest do certificado de assinatura nao encontrado."
    }
    $certificateSha256 = ($certificateLine.Line -split ":", 2)[1].Trim().ToUpperInvariant()
    $apkSha256 = (Get-FileHash -LiteralPath $targetApk -Algorithm SHA256).Hash
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $gitCommit = (& git rev-parse HEAD 2>$null).Trim()
    $gitStatus = @(& git status --porcelain 2>$null)
    $gitStatusExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $manifest = [ordered]@{
        schema_version = 1
        app_version = $resolvedVersion
        artifact = Split-Path -Leaf $targetApk
        size_bytes = (Get-Item -LiteralPath $targetApk).Length
        apk_sha256 = $apkSha256
        certificate_sha256 = $certificateSha256
        commit = $gitCommit
        clean_tree = ($gitStatusExitCode -eq 0 -and $gitStatus.Count -eq 0)
        backend_url = $BackendUrl
    }
    $manifest |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $outputDir "release-manifest.json") -Encoding UTF8
    Write-OK "APK: $targetApk"
    Write-OK "SHA256: $apkSha256"
    Write-OK "Manifest: $(Join-Path $outputDir 'release-manifest.json')"
}

Write-Host ""
Write-Host "====================================" -ForegroundColor Magenta
Write-Host "  Release build completed." -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Magenta

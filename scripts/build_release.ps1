param(
    [ValidateSet("android", "windows", "ios", "all")]
    [string]$Platform = "all",
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
        "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter.bat",
        "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter",
        "C:\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter"
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

    $localVersion = Get-LocalProperty "flutter.versionName"
    if ($localVersion) {
        return $localVersion
    }

    if (Test-Path $PubspecFile) {
        $match = Select-String -Path $PubspecFile -Pattern '^version:\s*([0-9A-Za-z.\-_]+)(?:\+\d+)?\s*$' | Select-Object -First 1
        if ($match) {
            return $match.Matches[0].Groups[1].Value.Trim()
        }
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

if ($Platform -in @("android", "all")) {
    Write-Step "Build Android APK"
    Invoke-Flutter -Arguments (@("build", "apk", "--release", "--no-pub") + $dartDefines)
    Write-OK "APK: build\\app\\outputs\\flutter-apk\\app-release.apk"

    Write-Step "Build Android AAB"
    Invoke-Flutter -Arguments (@("build", "appbundle", "--release", "--no-pub") + $dartDefines)
    Write-OK "AAB: build\\app\\outputs\\bundle\\release\\app-release.aab"
}

if ($Platform -in @("windows", "all")) {
    Write-Step "Build Windows EXE"
    Invoke-Flutter -Arguments (@("build", "windows", "--release", "--no-pub") + $dartDefines)
    Write-OK "EXE: build\\windows\\x64\\runner\\Release\\quiz_vance_flutter.exe"

    $zipPath = "build\\QuizVance-Windows-$resolvedVersion.zip"
    Compress-Archive `
        -Path "build\\windows\\x64\\runner\\Release\\*" `
        -DestinationPath $zipPath `
        -Force
    Write-OK "ZIP: $zipPath"
}

if ($Platform -eq "ios") {
    Write-Step "Build iOS (requires macOS + Xcode)"
    Invoke-Flutter -Arguments (@("build", "ios", "--release", "--no-codesign", "--no-pub") + $dartDefines)
    Write-OK "Archive: build\\ios\\archive\\Runner.xcarchive"
}

Write-Host ""
Write-Host "====================================" -ForegroundColor Magenta
Write-Host "  Release build completed." -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Magenta

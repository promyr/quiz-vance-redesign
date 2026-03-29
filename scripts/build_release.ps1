param(
    [ValidateSet("android", "windows", "ios", "all")]
    [string]$Platform = "all",
    [string]$BackendUrl = "https://quiz-vance-redesign-backend.fly.dev",
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PackageConfig = Join-Path $ProjectDir ".dart_tool\package_config.json"
$PubspecLock = Join-Path $ProjectDir "pubspec.lock"
Set-Location $ProjectDir

function Write-Step([string]$Message) {
    Write-Host "`n> $Message" -ForegroundColor Cyan
}

function Write-OK([string]$Message) {
    Write-Host "  OK $Message" -ForegroundColor Green
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

$dartDefine = "--dart-define=BACKEND_URL=$BackendUrl"
$script:FlutterCmd = Resolve-FlutterCommand
if (-not $script:FlutterCmd) {
    throw "Flutter nao encontrado."
}
Use-FlutterToolchain -FlutterCommand $script:FlutterCmd

Write-Step "Quiz Vance release build - platform: $Platform"
Write-Host "  Backend URL: $BackendUrl" -ForegroundColor Gray
Write-Host "  Version: $Version" -ForegroundColor Gray
Write-Host "  Flutter SDK: $script:FlutterCmd" -ForegroundColor Gray

Ensure-Dependencies

if ($Platform -in @("android", "all")) {
    Write-Step "Build Android APK"
    Invoke-Flutter -Arguments @("build", "apk", "--release", "--no-pub", $dartDefine)
    Write-OK "APK: build\\app\\outputs\\flutter-apk\\app-release.apk"

    Write-Step "Build Android AAB"
    Invoke-Flutter -Arguments @("build", "appbundle", "--release", "--no-pub", $dartDefine)
    Write-OK "AAB: build\\app\\outputs\\bundle\\release\\app-release.aab"
}

if ($Platform -in @("windows", "all")) {
    Write-Step "Build Windows EXE"
    Invoke-Flutter -Arguments @("build", "windows", "--release", "--no-pub", $dartDefine)
    Write-OK "EXE: build\\windows\\x64\\runner\\Release\\quiz_vance_flutter.exe"

    $zipPath = "build\\QuizVance-Windows-$Version.zip"
    Compress-Archive `
        -Path "build\\windows\\x64\\runner\\Release\\*" `
        -DestinationPath $zipPath `
        -Force
    Write-OK "ZIP: $zipPath"
}

if ($Platform -eq "ios") {
    Write-Step "Build iOS (requires macOS + Xcode)"
    Invoke-Flutter -Arguments @("build", "ios", "--release", "--no-codesign", "--no-pub", $dartDefine)
    Write-OK "Archive: build\\ios\\archive\\Runner.xcarchive"
}

Write-Host ""
Write-Host "====================================" -ForegroundColor Magenta
Write-Host "  Release build completed." -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Magenta

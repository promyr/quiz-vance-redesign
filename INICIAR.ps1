param(
    [string]$BackendUrl = "https://quiz-vance-redesign-backend.fly.dev"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PuroStableFlutter = Join-Path $env:USERPROFILE ".puro\envs\stable\flutter\bin\flutter.bat"

function Write-Step([string]$Message) {
    Write-Host "`n> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Resolve-FlutterCommand {
    if (Test-Path $PuroStableFlutter) {
        return $PuroStableFlutter
    }

    $puroCommand = Get-Command puro -ErrorAction SilentlyContinue
    if ($puroCommand) {
        try {
            & $puroCommand.Source flutter --version | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return $puroCommand.Source
            }
        } catch {
        }
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        return $flutterCommand.Source
    }

    $flutterExe = "C:\flutter\bin\flutter.bat"
    if (Test-Path $flutterExe) {
        $env:PATH = "C:\flutter\bin;$env:PATH"
        return $flutterExe
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

    if ($script:FlutterCmd -like "*puro.exe") {
        & $script:FlutterCmd flutter @Arguments
    } else {
        & $script:FlutterCmd @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Comando flutter falhou: flutter $($Arguments -join ' ')"
    }
}

function Ensure-WindowsPlatform {
    if (Test-Path (Join-Path $ProjectDir "windows")) {
        Write-Ok "Plataforma Windows ja configurada."
        return
    }

    Write-Step "Configurando plataforma Windows"
    $tempDir = Join-Path $env:TEMP "quiz_vance_windows_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Set-Location $tempDir
        Invoke-Flutter -Arguments @(
            "create",
            "--platforms", "windows",
            "--org", "com.quizvance",
            "."
        )

        $source = Join-Path $tempDir "windows"
        $destination = Join-Path $ProjectDir "windows"
        if (-not (Test-Path $source)) {
            Write-Fail "Flutter create nao gerou a pasta windows."
        }

        Copy-Item -Path $source -Destination $destination -Recurse -Force
        Write-Ok "Plataforma Windows configurada."
    } finally {
        Set-Location $ProjectDir
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$script:FlutterCmd = Resolve-FlutterCommand
if (-not $script:FlutterCmd) {
    Write-Fail "Flutter nao encontrado. Instale o SDK ou execute .\SETUP.ps1 primeiro."
}
Use-FlutterToolchain -FlutterCommand $script:FlutterCmd

Set-Location $ProjectDir

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Quiz Vance Flutter" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Cyan

Write-Ok "SDK selecionado: $script:FlutterCmd"

$pubspecLock = Join-Path $ProjectDir "pubspec.lock"
$packageConfig = Join-Path $ProjectDir ".dart_tool\package_config.json"
if ((-not (Test-Path $pubspecLock)) -or (-not (Test-Path $packageConfig))) {
    Write-Step "Instalando dependencias"
    Invoke-Flutter -Arguments @("pub", "get")
} else {
    Write-Ok "Dependencias ja preparadas."
}

Ensure-WindowsPlatform

Write-Step "Iniciando app no Windows"
Invoke-Flutter -Arguments @(
    "run",
    "-d", "windows",
    "--no-pub",
    "--dart-define=BACKEND_URL=$BackendUrl"
)

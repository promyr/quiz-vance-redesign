param(
    [string]$BackendUrl = "https://quiz-vance-redesign-backend.fly.dev",
    [switch]$SkipFlutterInstall,
    [switch]$RunAfterSetup
)

$ErrorActionPreference = "Stop"
$FlutterDir = "C:\flutter"
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

    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $flutterExe = Join-Path $FlutterDir "bin\flutter.bat"
    if (Test-Path $flutterExe) {
        $env:PATH = "$FlutterDir\bin;$env:PATH"
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

function Ensure-FlutterInstalled {
    $flutterCmd = Resolve-FlutterCommand
    if ($flutterCmd) {
        Write-Ok "Flutter encontrado em $flutterCmd"
        return $flutterCmd
    }

    if ($SkipFlutterInstall) {
        Write-Fail "Flutter nao encontrado e a instalacao foi ignorada."
    }

    Write-Step "Instalando Flutter SDK em $FlutterDir"
    if (-not (Test-Path $FlutterDir)) {
        $url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip"
        $zip = Join-Path $env:TEMP "flutter_windows_sdk.zip"
        Write-Host "  Baixando SDK..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Write-Host "  Extraindo SDK..." -ForegroundColor Gray
        Expand-Archive -Path $zip -DestinationPath "C:\" -Force
        Remove-Item $zip -Force
    } else {
        Write-Warn "Pasta $FlutterDir ja existe. Reutilizando instalacao local."
    }

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$FlutterDir\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$FlutterDir\bin;$userPath", "User")
        Write-Ok "Flutter adicionado ao PATH do usuario"
    }

    $flutterCmd = Resolve-FlutterCommand
    if (-not $flutterCmd) {
        Write-Fail "Flutter nao foi encontrado apos a instalacao."
    }

    return $flutterCmd
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

function Ensure-Platforms {
    Write-Step "Configurando plataformas Flutter"
    $requiredPlatforms = @("android", "ios", "windows")
    $missingPlatforms = $requiredPlatforms | Where-Object {
        -not (Test-Path (Join-Path $ProjectDir $_))
    }

    if ($missingPlatforms.Count -eq 0) {
        Write-Ok "Plataformas principais ja configuradas."
        return
    }

    # Create in temp directory to avoid overwriting lib/ and pubspec.yaml
    $tempDir = Join-Path $env:TEMP "quiz_vance_temp_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "  Criando projeto em diretorio temporario..." -ForegroundColor Gray
    Set-Location $tempDir
    Invoke-Flutter -Arguments @(
        "create",
        "--platforms", "android,ios,windows,linux,macos",
        "--org", "com.quizvance",
        "."
    )

    Write-Host "  Copiando pastas de plataforma..." -ForegroundColor Gray
    Set-Location $ProjectDir
    foreach ($platform in $requiredPlatforms) {
        $source = Join-Path $tempDir $platform
        $destination = Join-Path $ProjectDir $platform
        if (Test-Path $source) {
            Remove-Item $destination -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -Path $source -Destination $destination -Recurse -Force
            Write-Host "    Copiado: $platform" -ForegroundColor Gray
        }
    }

    # Cleanup temp directory
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

    Write-Ok "Plataformas geradas/atualizadas. lib/ e pubspec.yaml preservados."
}

$script:FlutterCmd = Ensure-FlutterInstalled
Use-FlutterToolchain -FlutterCommand $script:FlutterCmd
Write-Ok "SDK selecionado: $script:FlutterCmd"

Write-Step "Executando flutter doctor"
if ($script:FlutterCmd -like "*puro.exe") {
    & $script:FlutterCmd flutter doctor
} else {
    & $script:FlutterCmd doctor
}
if ($LASTEXITCODE -ne 0) {
    Write-Warn "flutter doctor reportou pendencias. O setup vai continuar."
}

Set-Location $ProjectDir
Ensure-Platforms

Write-Step "Instalando dependencias"
Invoke-Flutter -Arguments @("pub", "get")

Write-Step "Executando analise estatica"
Invoke-Flutter -Arguments @("analyze", "--no-pub")

Write-Step "Executando testes"
Invoke-Flutter -Arguments @("test", "--no-pub")

if ($RunAfterSetup) {
    Write-Step "Abrindo o app no Windows"
    if ($script:FlutterCmd -like "*puro.exe") {
        & $script:FlutterCmd flutter run -d windows --no-pub "--dart-define=BACKEND_URL=$BackendUrl"
    } else {
        & $script:FlutterCmd run -d windows --no-pub "--dart-define=BACKEND_URL=$BackendUrl"
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Falha ao executar o app no Windows."
    }
} else {
    Write-Host ""
    Write-Host "Setup concluido." -ForegroundColor Green
    Write-Host "Para abrir o app agora, execute:" -ForegroundColor White
    Write-Host "  .\SETUP.ps1 -RunAfterSetup" -ForegroundColor Cyan
}

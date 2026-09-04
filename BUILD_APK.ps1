param(
    [string]$BackendUrl = ""
)

$ErrorActionPreference = "Continue"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendConfigFile = Join-Path $ProjectDir "backend_url.txt"
$LogFile = Join-Path $ProjectDir "build_log.txt"
$LocalPropertiesFile = Join-Path $ProjectDir "android\local.properties"
$PackageConfig = Join-Path $ProjectDir ".dart_tool\package_config.json"
$PubspecLock = Join-Path $ProjectDir "pubspec.lock"
$PubspecFile = Join-Path $ProjectDir "pubspec.yaml"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $Message -Encoding UTF8
}

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

    return ($line -replace '^[^=]+=','') -replace '\\\\','\'
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

function Resolve-FlutterPath {
    $candidates = @(
        "C:\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter",
        "C:\src\flutter\bin\flutter.bat",
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

function Resolve-SdkPath {
    $candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        "$env:USERPROFILE\Android\sdk",
        (Get-LocalProperty "sdk.dir"),
        "$env:LOCALAPPDATA\Android\Sdk",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe"
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (
            (Test-Path $candidate) -and
            (Test-Path (Join-Path $candidate "platform-tools"))
        ) {
            return $candidate
        }
    }

    return $null
}

function Update-LocalPropertiesSdk {
    param([string]$SdkPath)

    if (-not $SdkPath) {
        return
    }

    $sdkLine = "sdk.dir=$($SdkPath -replace '\\','\\\\')"
    $lines = @()
    if (Test-Path $LocalPropertiesFile) {
        $lines = Get-Content $LocalPropertiesFile | Where-Object { $_ -notlike "sdk.dir=*" }
    }

    @($sdkLine) + $lines | Set-Content -Path $LocalPropertiesFile -Encoding UTF8
}

function Resolve-SdkManager {
    param([string]$SdkPath)

    if (-not $SdkPath -or -not (Test-Path $SdkPath)) {
        return $null
    }

    $candidates = @(
        (Join-Path $SdkPath "cmdline-tools\latest\bin\sdkmanager.bat")
    )

    $cmdlineToolsDir = Join-Path $SdkPath "cmdline-tools"
    if (Test-Path $cmdlineToolsDir) {
        $candidates += Get-ChildItem $cmdlineToolsDir -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "bin\sdkmanager.bat" }
    }

    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Resolve-AppVersion {
    $localVersion = Get-LocalProperty "flutter.versionName"
    if ($localVersion) {
        return $localVersion.Trim()
    }

    if (Test-Path $PubspecFile) {
        $match = Select-String -Path $PubspecFile -Pattern '^version:\s*([0-9A-Za-z.\-_]+)(?:\+\d+)?\s*$' | Select-Object -First 1
        if ($match) {
            return $match.Matches[0].Groups[1].Value.Trim()
        }
    }

    return "1.0.0"
}

function Ensure-Dependencies {
    if ((Test-Path $PubspecLock) -and (Test-Path $PackageConfig)) {
        Write-Log "[OK] Dependencias ja preparadas. Build seguira com --no-pub." "Green"
        return
    }

    Write-Log "[1/4] flutter pub get --offline" "Yellow"
    & $Flutter pub get --offline 2>&1 | Tee-Object -Append -FilePath $LogFile
    if ($LASTEXITCODE -eq 0) {
        Write-Log ""
        return
    }

    Write-Log ""
    Write-Log "[INFO] Cache offline insuficiente. Tentando flutter pub get online..." "Yellow"
    & $Flutter pub get 2>&1 | Tee-Object -Append -FilePath $LogFile
    if ($LASTEXITCODE -ne 0) {
        Write-Log ""
        Write-Log "[ERRO] flutter pub get falhou." "Red"
        Read-Host "Pressione Enter para fechar"
        exit 1
    }
    Write-Log ""
}

function Invoke-FlutterLogged {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $quotedFlutter = '"' + $Flutter + '"'
    $commandLine = "$quotedFlutter $($Arguments -join ' ')"

    try {
        $process = Start-Process `
            -FilePath "C:\Windows\System32\cmd.exe" `
            -ArgumentList "/c", $commandLine `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        if (Test-Path $stdoutFile) {
            Get-Content $stdoutFile | Tee-Object -Append -FilePath $LogFile | Out-Host
        }
        if (Test-Path $stderrFile) {
            Get-Content $stderrFile | Tee-Object -Append -FilePath $LogFile | Out-Host
        }

        return [int]$process.ExitCode
    } finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Show-AndroidSdkHelp {
    param([string]$SdkPath)

    Write-Log "[ERRO] Android SDK incompleto ou sem cmdline-tools." "Red"
    Write-Log ""
    Write-Log "SDK detectado: $SdkPath"
    Write-Log ""
    Write-Log "Para corrigir:"
    Write-Log "  1. Abra o Android Studio"
    Write-Log "  2. SDK Manager > instale 'Android SDK Command-line Tools (latest)'"
    Write-Log "  3. SDK Manager > instale 'NDK (Side by side) 28.2.13676358'"
    Write-Log "  4. Execute: puro flutter doctor --android-licenses"
    Write-Log "  5. Ajuste android\\local.properties para:"
    Write-Log "     sdk.dir=$env:USERPROFILE\\Android\\sdk"
    Write-Log ""
    Read-Host "Pressione Enter para fechar"
}

"" | Set-Content $LogFile -Encoding UTF8

Write-Log "=====================================================" "Cyan"
Write-Log "  QUIZ VANCE - BUILD APK ANDROID"
Write-Log "  $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Write-Log "=====================================================" "Cyan"
Write-Log ""

$Flutter = Resolve-FlutterPath
if (-not $Flutter) {
    Write-Log "[ERRO] Flutter nao encontrado." "Red"
    Read-Host "Pressione Enter para fechar"
    exit 1
}

Set-Location $ProjectDir
$BackendUrl = Resolve-BackendUrl -CliValue $BackendUrl
$AppVersion = Resolve-AppVersion

Write-Log "[OK] Flutter encontrado: $Flutter" "Green"
Write-Log "[INFO] Projeto: $ProjectDir"
Write-Log "[INFO] App version header: $AppVersion"
Write-Log ""

$SdkPath = Resolve-SdkPath
$SdkManager = Resolve-SdkManager -SdkPath $SdkPath
Write-Log "[DIAG] Android SDK: $SdkPath" "Yellow"
Write-Log "[DIAG] sdkmanager: $SdkManager" "Yellow"
Write-Log ""

if (-not $SdkPath -or -not $SdkManager) {
    Show-AndroidSdkHelp -SdkPath $SdkPath
    exit 1
}

$env:ANDROID_HOME = $SdkPath
$env:ANDROID_SDK_ROOT = $SdkPath
Update-LocalPropertiesSdk -SdkPath $SdkPath

Write-Log "[DIAG] flutter --version:" "Yellow"
$versionExitCode = Invoke-FlutterLogged -Arguments @("--version")
Write-Log ""
if ($versionExitCode -ne 0) {
    Write-Log "[ERRO] Nao foi possivel consultar a versao do Flutter." "Red"
    Read-Host "Pressione Enter para fechar"
    exit 1
}

Ensure-Dependencies

Write-Log "[2/3] flutter build apk --release (production universal)" "Yellow"
Write-Log ""

$buildExitCode = Invoke-FlutterLogged -Arguments @(
    "build",
    "apk",
    "--release",
    "--flavor",
    "production",
    "--no-pub",
    "--dart-define=BACKEND_URL=$BackendUrl",
    "--dart-define=APP_VERSION=$AppVersion"
)
if ($buildExitCode -ne 0) {
    Write-Log ""
    Write-Log "[ERRO] Build universal falhou. Leia o log acima." "Red"
    Write-Log "Log completo salvo em: $LogFile"
    Read-Host "Pressione Enter para abrir o log no Notepad"
    Start-Process notepad $LogFile
    exit 1
}

Write-Log ""
Write-Log "[3/3] Copiando APK final..." "Yellow"

$OutputDir = Join-Path $ProjectDir "output_apk"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Get-ChildItem -Path $OutputDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".apk", ".aab") } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$universalSource = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-production-release.apk"

if (-not (Test-Path $universalSource)) {
    Write-Log "[ERRO] APK universal nao encontrado apos o build." "Red"
    Write-Log "Log completo salvo em: $LogFile"
    Read-Host "Pressione Enter para abrir o log no Notepad"
    Start-Process notepad $LogFile
    exit 1
}

$universalTarget = Join-Path $OutputDir "app-universal-release.apk"
Copy-Item $universalSource -Destination $universalTarget -Force
Write-Log "  -> app-universal-release.apk" "Green"

Start-Process explorer $OutputDir

Write-Log ""
Write-Log "Log completo: $LogFile"
Read-Host "Pressione Enter para fechar"

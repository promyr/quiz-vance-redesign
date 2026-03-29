$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$PuroStableFlutter = Join-Path $env:USERPROFILE ".puro\envs\stable\flutter\bin\flutter.bat"

function Resolve-FlutterCommand {
    $candidates = @(
        $PuroStableFlutter,
        "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter",
        "C:\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        return $flutterCommand.Source
    }

    throw 'Flutter nao encontrado para qa_smoke.'
}

function Use-FlutterToolchain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FlutterCommand
    )

    $flutterBin = Split-Path -Parent $FlutterCommand
    $script:DartCommand = Join-Path $flutterBin "dart.bat"
    if (-not (Test-Path $script:DartCommand)) {
        $script:DartCommand = Join-Path $flutterBin "dart"
    }
    $script:FlutterCommand = $FlutterCommand
    $env:PATH = "$flutterBin;$env:PATH"
}

function Assert-LastExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$CommandName falhou com exit code $LASTEXITCODE."
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "[qa_smoke] START $Name"

    try {
        & $Action
        $watch.Stop()
        Write-Host ("[qa_smoke] OK    {0} ({1:n2}s)" -f $Name, $watch.Elapsed.TotalSeconds)
    } catch {
        $watch.Stop()
        Write-Host ("[qa_smoke] FAIL  {0} ({1:n2}s)" -f $Name, $watch.Elapsed.TotalSeconds) -ForegroundColor Red
        throw
    }
}

Push-Location $root
try {
    Use-FlutterToolchain -FlutterCommand (Resolve-FlutterCommand)

    Invoke-Step -Name 'bootstrap package_config' -Action {
        if (-not (Test-Path '.dart_tool/package_config.json')) {
            & $script:FlutterCommand pub get
            Assert-LastExitCode -CommandName 'flutter pub get'
        } else {
            Write-Host '[qa_smoke] package_config.json ja existe, pulando flutter pub get.'
        }
    }

    Invoke-Step -Name 'check mojibake' -Action {
        powershell -ExecutionPolicy Bypass -File scripts/check_mojibake.ps1
    }

    Invoke-Step -Name 'targeted analyze' -Action {
        & $script:DartCommand analyze `
            lib/features/auth `
            lib/features/home `
            lib/features/flashcard `
            lib/features/profile `
            lib/shared/providers `
            test/features/auth/auth_repository_test.dart `
            test/features/home/home_screen_test.dart `
            test/features/flashcard/flashcard_flow_test.dart `
            test/features/profile/billing_repository_test.dart `
            test/features/profile/premium_screen_test.dart `
            test/shared/providers/auth_provider_bootstrap_test.dart
        Assert-LastExitCode -CommandName 'dart analyze'
    }

    Invoke-Step -Name 'targeted tests' -Action {
        & $script:FlutterCommand test `
            test/features/auth/auth_repository_test.dart `
            test/shared/providers/auth_provider_bootstrap_test.dart `
            test/features/home/home_screen_test.dart `
            test/features/flashcard/flashcard_flow_test.dart `
            test/features/profile/billing_repository_test.dart `
            test/features/profile/premium_screen_test.dart
        Assert-LastExitCode -CommandName 'flutter test'
    }
} finally {
    Pop-Location
}

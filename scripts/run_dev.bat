@echo off
:: Roda o app em modo desenvolvimento com hot reload
:: Uso: run_dev.bat [windows|android|chrome]
setlocal

set PLATFORM=%1
if "%PLATFORM%"=="" set PLATFORM=windows

set BACKEND_URL=%2
if not "%QUIZ_VANCE_BACKEND_URL%"=="" set "BACKEND_URL=%QUIZ_VANCE_BACKEND_URL%"
if "%BACKEND_URL%"=="" (
    for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$path = Join-Path '%~dp0\..' 'backend_url.txt'; if (Test-Path $path) { Get-Content $path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1 }"`) do (
        set "BACKEND_URL=%%i"
    )
)
if "%BACKEND_URL%"=="" set BACKEND_URL=https://quiz-vance-redesign-backend.fly.dev

cd /d "%~dp0\.."

echo.
echo  Quiz Vance — Dev Mode
echo  Plataforma : %PLATFORM%
echo  Backend    : %BACKEND_URL%
echo.

flutter run -d %PLATFORM% --dart-define=BACKEND_URL=%BACKEND_URL%

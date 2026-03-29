@echo off
:: Roda o app em modo desenvolvimento com hot reload
:: Uso: run_dev.bat [windows|android|chrome]
setlocal

set PLATFORM=%1
if "%PLATFORM%"=="" set PLATFORM=windows

set BACKEND_URL=%2
if "%BACKEND_URL%"=="" set BACKEND_URL=https://quiz-vance-redesign-backend.fly.dev

cd /d "%~dp0\.."

echo.
echo  Quiz Vance — Dev Mode
echo  Plataforma : %PLATFORM%
echo  Backend    : %BACKEND_URL%
echo.

flutter run -d %PLATFORM% --dart-define=BACKEND_URL=%BACKEND_URL%

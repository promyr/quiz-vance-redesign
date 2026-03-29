@echo off
setlocal EnableDelayedExpansion
chcp 65001
title Quiz Vance - Setup
cd /d "%~dp0"

echo.
echo  =============================================
echo   Quiz Vance Flutter - Setup Completo
echo  =============================================
echo.

set "FLUTTER_CMD="

if exist "%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat" (
    set "FLUTTER_CMD=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat"
) else (
    where flutter 2>NUL
    if %ERRORLEVEL% EQU 0 set "FLUTTER_CMD=flutter"
)
if exist "C:\flutter\bin\flutter.bat" (
    if not defined FLUTTER_CMD (
        set "FLUTTER_CMD=C:\flutter\bin\flutter.bat"
        set "PATH=C:\flutter\bin;%PATH%"
    )
)

if not defined FLUTTER_CMD (
    echo  [ERRO] Flutter nao encontrado.
    echo  Instale em: https://docs.flutter.dev/get-started/install/windows
    pause
    exit /b 1
)

echo  [SDK] %FLUTTER_CMD%
echo.

echo  [1/4] Instalando dependencias...
call "%FLUTTER_CMD%" pub get
if %ERRORLEVEL% NEQ 0 ( echo  [ERRO] pub get falhou. & pause & exit /b 1 )
echo  [OK]
echo.

if not exist "windows\" (
    echo  [2/4] Configurando plataforma Windows...
    set "TEMP_DIR=%TEMP%\qv_%RANDOM%"
    mkdir "!TEMP_DIR!"
    cd /d "!TEMP_DIR!"
    call "%FLUTTER_CMD%" create --platforms windows --org com.quizvance .
    if exist "!TEMP_DIR!\windows\" (
        xcopy "!TEMP_DIR!\windows" "%~dp0windows\" /E /I /Q /Y 1>NUL
        echo  [OK] Windows configurado.
    )
    cd /d "%~dp0"
    rmdir /s /q "!TEMP_DIR!" 2>NUL
) else (
    echo  [2/4] Plataforma Windows ja configurada.
)
echo.

echo  [3/4] Analise estatica...
call "%FLUTTER_CMD%" analyze
echo.

echo  [4/4] Testes...
call "%FLUTTER_CMD%" test
echo.

echo  =============================================
echo   Concluido! Execute INICIAR.bat para abrir.
echo  =============================================
echo.
pause

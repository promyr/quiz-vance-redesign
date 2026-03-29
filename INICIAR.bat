@echo off
setlocal EnableDelayedExpansion
chcp 65001
title Quiz Vance
cd /d "%~dp0"

echo.
echo  =============================================
echo   Quiz Vance Flutter
echo  =============================================
echo.

set "FLUTTER_CMD="

if exist "%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat" (
    set "FLUTTER_CMD=%USERPROFILE%\.puro\envs\stable\flutter\bin\flutter.bat"
    echo  [OK] Flutter via puro encontrado.
    goto :tem_flutter
)

where flutter 2>NUL
if %ERRORLEVEL% EQU 0 (
    set "FLUTTER_CMD=flutter"
    echo  [OK] Flutter encontrado no PATH.
    goto :tem_flutter
)

if exist "C:\flutter\bin\flutter.bat" (
    set "FLUTTER_CMD=C:\flutter\bin\flutter.bat"
    set "PATH=C:\flutter\bin;%PATH%"
    echo  [OK] Flutter encontrado em C:\flutter.
    goto :tem_flutter
)

echo  [AVISO] Flutter nao encontrado.
echo  Instale em: https://docs.flutter.dev/get-started/install/windows
echo  Depois abra este arquivo novamente.
echo.
pause
exit /b 1

:tem_flutter
echo.

if not exist "pubspec.lock" (
    echo  [1/2] Instalando dependencias...
    call "%FLUTTER_CMD%" pub get
    if %ERRORLEVEL% NEQ 0 (
        echo  [ERRO] flutter pub get falhou.
        pause
        exit /b 1
    )
) else (
    echo  [1/2] Dependencias ja instaladas.
)

if not exist "windows\" (
    echo  [2/2] Configurando plataforma Windows...
    set "TEMP_DIR=%TEMP%\qv_%RANDOM%"
    mkdir "!TEMP_DIR!"
    cd /d "!TEMP_DIR!"
    call "%FLUTTER_CMD%" create --platforms windows --org com.quizvance .
    if exist "!TEMP_DIR!\windows\" (
        xcopy "!TEMP_DIR!\windows" "%~dp0windows\" /E /I /Q /Y 1>NUL
        echo  [OK] Plataforma Windows configurada.
    )
    cd /d "%~dp0"
    rmdir /s /q "!TEMP_DIR!" 2>NUL
) else (
    echo  [2/2] Plataforma Windows ja configurada.
)

echo.
echo  Iniciando app... (Ctrl+C para parar)
echo.
call "%FLUTTER_CMD%" run -d windows --no-pub

echo.
pause

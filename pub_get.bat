@echo off
title Quiz Vance — Setup
cd /d "%~dp0"

echo.
echo ================================================
echo   Quiz Vance Redesign — Resolvendo dependencias
echo ================================================
echo.

:: 1) Limpa artefatos antigos de build
echo [1/3] Limpando build anterior...
flutter clean
if %ERRORLEVEL% NEQ 0 (
    echo AVISO: flutter clean falhou, continuando mesmo assim...
)
echo.

:: 2) Baixa / atualiza pacotes
echo [2/3] Rodando flutter pub get...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERRO: flutter pub get falhou!
    echo Verifique sua conexao com a internet e tente novamente.
    pause
    exit /b 1
)
echo.

:: 3) Verifica se ha erros de analise nos arquivos novos
echo [3/3] Analisando novos arquivos...
flutter analyze lib/features/estudar/presentation/estudar_screen.dart lib/features/home/presentation/home_screen.dart lib/shared/widgets/app_bottom_nav.dart 2>&1
echo.

echo ================================================
echo   CONCLUIDO! Agora va ao IntelliJ e clique em
echo   "Run" para iniciar o app.
echo ================================================
echo.
pause

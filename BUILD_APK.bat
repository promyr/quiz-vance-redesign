@echo off
:: Lanca o script PowerShell com permissao de execucao
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_APK.ps1"

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Read-ProjectFile([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Arquivo obrigatório ausente: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $path -Encoding UTF8
}

function Assert-Matches(
    [string]$Source,
    [string]$Pattern,
    [string]$Message
) {
    if ($Source -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatches(
    [string]$Source,
    [string]$Pattern,
    [string]$Message
) {
    if ($Source -match $Pattern) {
        throw $Message
    }
}

$workflow = Read-ProjectFile '.github/workflows/build.yml'
$gradle = Read-ProjectFile 'android/app/build.gradle'
$dockerfile = Read-ProjectFile 'backend/Dockerfile'
$dockerIgnore = Read-ProjectFile 'backend/.dockerignore'
$flyConfig = Read-ProjectFile 'backend/fly.toml'
$buildApk = Read-ProjectFile 'BUILD_APK.ps1'
$buildRelease = Read-ProjectFile 'scripts/build_release.ps1'
$telegramPublisher = Read-ProjectFile 'backend/scripts/publish_telegram_release_link.py'

Assert-Matches $workflow '(?m)uses:\s+[^@\r\n]+@[0-9a-f]{40}(?:\s+#.*)?$' `
    'As GitHub Actions devem ser fixadas por SHA imutável.'
Assert-NotMatches $workflow 'uses:\s+[^@\r\n]+@v\d+' `
    'Tags mutáveis de GitHub Actions não são permitidas.'
Assert-Matches $workflow '--flavor[=\s]+production' `
    'O CI deve construir explicitamente o flavor production.'
Assert-Matches $workflow '--dart-define=APP_VERSION=' `
    'O CI deve injetar APP_VERSION da mesma versão do pubspec.'
Assert-NotMatches $workflow '--split-per-abi|android-apk-split|build-windows|windows-build' `
    'O canal oficial deve gerar somente um APK universal Android.'
Assert-Matches $workflow 'pytest' 'O CI deve executar testes do backend.'
Assert-Matches $workflow 'ruff' 'O CI deve executar Ruff no backend.'
Assert-Matches $workflow 'bandit' 'O CI deve executar Bandit no backend.'
Assert-Matches $workflow 'sbom-action' 'O CI deve gerar SBOM.'
Assert-Matches $workflow 'scan-action' 'O CI deve escanear a imagem.'
Assert-Matches $workflow 'node scripts/check_secret_hygiene\.mjs' `
    'O CI deve bloquear regressões de secrets antes do build.'
Assert-Matches $workflow 'ANDROID_KEYSTORE_BASE64' `
    'O CI deve materializar o keystore apenas a partir de secret.'

Assert-Matches $gradle 'throw new GradleException' `
    'Release sem signing config deve falhar fechado.'
Assert-NotMatches $gradle 'signingConfigs\.debug' `
    'Release nunca pode usar assinatura debug como fallback.'

Assert-Matches $dockerfile '(?m)^USER\s+\d+' `
    'A imagem de produção deve executar como usuário não-root.'
Assert-Matches $dockerfile 'scripts/publish_telegram_release_link\.py' `
    'A imagem deve incluir o publicador atômico do Telegram.'
Assert-Matches $dockerIgnore '!scripts/publish_telegram_release_link\.py' `
    'O contexto Docker deve liberar somente o publicador do Telegram.'
Assert-NotMatches $dockerfile '(?m)^CMD.*alembic\s+upgrade' `
    'Migration não pode executar em todo startup do app.'
Assert-Matches $flyConfig 'release_command\s*=\s*"alembic upgrade head"' `
    'Fly deve executar migration uma vez como release command.'

Assert-Matches $buildApk 'quiz-vance-\$AppVersion-universal\.apk' `
    'O entrypoint Android deve produzir somente nome canônico versionado.'
Assert-Matches $buildApk 'apksigner' `
    'O entrypoint Android deve validar assinatura.'
Assert-Matches $buildApk 'SHA256' `
    'O entrypoint Android deve registrar SHA-256.'
Assert-NotMatches $buildApk 'Remove-Item.+\.apk' `
    'Build não deve apagar APKs históricos sem autorização.'

Assert-Matches $buildRelease '\[string\]\$Platform = "android"' `
    'O release geral deve usar Android como padrão.'
Assert-Matches $buildRelease 'apksigner' `
    'Todo entrypoint oficial deve validar a assinatura do APK.'
Assert-Matches $buildRelease 'release-manifest\.json' `
    'Todo entrypoint oficial deve gravar o manifesto de proveniência.'
Assert-NotMatches $buildRelease 'Build Windows|Build iOS|build appbundle' `
    'Plataformas removidas e artefatos paralelos devem ficar fora do release oficial.'

Assert-Matches $telegramPublisher '_verify_remote_release' `
    'O publicador deve comparar tamanho e hash baixados do link público.'
Assert-NotMatches $telegramPublisher 'unpinChatMessage' `
    'O publicador não deve remover o pin saudável antes de confirmar o substituto.'

Write-Output 'PASS: política de release fail-closed e universal está aplicada.'

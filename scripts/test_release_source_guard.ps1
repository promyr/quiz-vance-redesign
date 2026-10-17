$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release_source_guard.ps1')
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('quiz-source-guard-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert-Blocked([scriptblock]$Action) {
    $blocked = $false
    try { & $Action | Out-Null } catch { $blocked = $true }
    if (-not $blocked) { throw 'Esperado bloqueio da release.' }
}
try {
    Assert-Blocked { Assert-ReleaseSourceState -Repository $fixture }
    & git -C $fixture init --quiet
    'original' | Set-Content (Join-Path $fixture 'source.txt')
    & git -C $fixture add source.txt
    & git -C $fixture -c user.name=QA -c user.email=qa@example.invalid commit --quiet -m initial
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar fixture Git.' }
    $state = Assert-ReleaseSourceState -Repository $fixture
    if (-not $state.clean_tree) { throw 'Arvore limpa deveria ser aceita.' }
    'modified' | Set-Content (Join-Path $fixture 'source.txt')
    Assert-Blocked { Assert-ReleaseSourceState -Repository $fixture }
    & git -C $fixture checkout -- source.txt
    'new' | Set-Content (Join-Path $fixture 'new.txt')
    Assert-Blocked { Assert-ReleaseSourceState -Repository $fixture }
    & git -C $fixture add new.txt
    & git -C $fixture -c user.name=QA -c user.email=qa@example.invalid commit --quiet -m next
    Assert-Blocked { Assert-ReleaseSourceState -Repository $fixture -ExpectedCommit $state.commit }
    Assert-ReleaseSourceState -Repository $fixture | Out-Null
    Write-Output 'PASS: release aceita fontes commitadas e bloqueia Git invalido, alteracoes, arquivos novos e troca de commit.'
} finally {
    $resolved = [System.IO.Path]::GetFullPath($fixture)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf).StartsWith('quiz-source-guard-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

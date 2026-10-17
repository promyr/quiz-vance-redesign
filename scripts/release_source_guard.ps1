function Assert-ReleaseSourceState {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [string]$ExpectedCommit = ''
    )
    $commit = & git -C $Repository -c core.fsmonitor=false rev-parse --verify HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $commit) {
        throw 'Release bloqueada: nao foi possivel identificar o commit Git.'
    }
    $status = @(& git -C $Repository -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Release bloqueada: nao foi possivel verificar o estado Git.'
    }
    if ($status.Count -gt 0) {
        throw 'Release bloqueada: existem alteracoes ou arquivos novos sem commit. Preserve e versione as fontes antes do build.'
    }
    $commit = ([string]$commit).Trim()
    if ($ExpectedCommit -and $commit -ne $ExpectedCommit) {
        throw 'Release bloqueada: o commit mudou durante o build.'
    }
    return @{ commit = $commit; clean_tree = $true }
}

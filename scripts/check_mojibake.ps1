$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$replacementChar = [string][char]0xFFFD

$patterns = @(
    ([string][char]0x00C3) + '.',
    ([string][char]0x00C2) + '.',
    ([string][char]0x00E2) + [string][char]0x20AC,
    ([string][char]0x00F0) + [string][char]0x0178,
    ([string][char]0x00C3) + [string][char]0x0192,
    ([string][char]0x00C3) + [string][char]0x00A2,
    ([string][char]0x00EF) + [string][char]0x00B8,
    $replacementChar
)

$targets = @(
    @{ Path = (Join-Path $root 'lib'); Filter = '*.dart' },
    @{ Path = (Join-Path $root 'test'); Filter = '*.dart' },
    @{ Path = (Join-Path $root 'scripts'); Filter = '*.ps1' }
)

$matchesFound = @()

foreach ($target in $targets) {
    if (-not (Test-Path $target.Path)) {
        continue
    }

    $files = Get-ChildItem -Path $target.Path -Recurse -File -Filter $target.Filter
    foreach ($file in $files) {
        if ($file.FullName -eq $PSCommandPath) {
            continue
        }

        $lineNumber = 0
        foreach ($line in Get-Content -Path $file.FullName) {
            $lineNumber++
            foreach ($pattern in $patterns) {
                if ($line -match $pattern) {
                    $relative = $file.FullName.Substring($root.Length + 1)
                    $matchesFound += [pscustomobject]@{
                        File = $relative
                        Line = $lineNumber
                        Text = $line.Trim()
                    }
                    break
                }
            }
        }
    }
}

if ($matchesFound.Count -gt 0) {
    Write-Host '[check_mojibake] Sequencias suspeitas encontradas:' -ForegroundColor Red
    foreach ($match in $matchesFound) {
        Write-Host ('{0}:{1} -> {2}' -f $match.File, $match.Line, $match.Text)
    }
    exit 1
}

Write-Host '[check_mojibake] Nenhuma sequencia suspeita encontrada.' -ForegroundColor Green

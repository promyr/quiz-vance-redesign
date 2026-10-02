$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'build_release.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Release script has syntax errors.' }
# Load only pure helpers; never execute the build script or resolve a toolchain.
foreach ($name in @('Get-LocalProperty', 'Resolve-AppVersion', 'Get-ReleaseBuildArguments')) {
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
}
$PubspecFile = Join-Path $PSScriptRoot '__missing_pubspec__'
$LocalPropertiesFile = Join-Path $PSScriptRoot '__missing_local_properties__'
$Version = '2.0.99+98'
if ((Resolve-AppVersion) -ne $Version) { throw 'Explicit version was not preserved.' }
foreach ($invalid in @('', '2.0.99', '../bad+98', '2.0.99+0', '2.0.99+2100000001')) {
    $Version = $invalid
    $rejected = $false
    try { $null = Resolve-AppVersion } catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid or missing version accepted: '$invalid'" }
}
$Version = ''
$PubspecFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'pubspec.yaml'
$resolved = Resolve-AppVersion
if ($resolved -notmatch '^\d+\.\d+\.\d+\+\d+$') { throw 'Pubspec version was not resolved.' }
$arguments = @(Get-ReleaseBuildArguments -AppVersion '2.0.99+98' -Backend 'https://example.test')
foreach ($expected in @('--build-name=2.0.99', '--build-number=98', '--dart-define=APP_VERSION=2.0.99+98', '--dart-define=BACKEND_URL=https://example.test', '--no-pub')) {
    if ($arguments -notcontains $expected) { throw "Missing build argument: $expected" }
}
Write-Host 'Release version tests passed (resolution, invalid input, native and Dart version alignment).'

$launcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'BUILD_APK.ps1'
$launcherAst = [System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'APK launcher has syntax errors.' }
$definition = $launcherAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-AppVersion' }, $true)
. ([scriptblock]::Create($definition.Extent.Text))
$PubspecFile = Join-Path $PSScriptRoot '__missing_pubspec__'
$rejected = $false
try { $null = Resolve-AppVersion } catch { $rejected = $true }
if (-not $rejected) { throw 'Launcher accepted a missing canonical version.' }
$PubspecFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'pubspec.yaml'
if ((Resolve-AppVersion) -ne $resolved) { throw 'Launchers disagree on canonical version.' }
$launcherText = $launcherAst.Extent.Text
foreach ($argument in @('--build-name=$buildName', '--build-number=$buildNumber')) {
    if (-not $launcherText.Contains($argument)) { throw "Launcher is missing $argument" }
}
Write-Host 'APK launcher version tests passed.'

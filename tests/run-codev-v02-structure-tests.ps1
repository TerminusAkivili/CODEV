$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if ($Text -notlike "*$Needle*") {
        throw "$Message Missing '$Needle'."
    }
}

$expectedSkills = @(
    "using-codev",
    "codev-shape",
    "codev-gate",
    "codev-drift"
)

$skillDirs = Get-ChildItem -LiteralPath (Join-Path $root "skills") -Directory | Select-Object -ExpandProperty Name | Sort-Object
Assert-Equal ($skillDirs -join ",") (($expectedSkills | Sort-Object) -join ",") "Skill set should be lightweight v0.2."

$skillFiles = Get-ChildItem -Path (Join-Path $root "skills") -Recurse -Filter "SKILL.md"
Assert-Equal $skillFiles.Count 4 "There should be exactly four skill files."

foreach ($skillFile in $skillFiles) {
    $text = Get-Content -Raw -LiteralPath $skillFile.FullName
    Assert-True ($text -match "(?s)^---\s*.*name:\s*[-a-z0-9]+.*description:\s*.+?---") "Invalid frontmatter: $($skillFile.FullName)"
}

$templateFiles = Get-ChildItem -LiteralPath (Join-Path $root "templates") -File | Select-Object -ExpandProperty Name | Sort-Object
Assert-Equal ($templateFiles -join ",") "codev.md" "Default templates should be single-file."

$readme = Get-Content -Raw -LiteralPath (Join-Path $root "README.md")
Assert-Contains $readme "Ceremony" "README should explain ceremony weight."
Assert-Contains $readme ".codev.md" "README should document the default state file."
Assert-Contains $readme "ultra + light" "README should recommend lightweight frequent gates."
Assert-Contains $readme "Roadmap is coarse-grained" "README should keep roadmap coarse."
Assert-Contains $readme "Trace is fine-grained" "README should keep trace fine-grained."

$shapeSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-shape\SKILL.md")
Assert-Contains $shapeSkill "Roadmap/shape is big-picture and coarse-grained" "Shape skill should prevent roadmap task logs."
Assert-Contains $shapeSkill "Trace is small and fine-grained, but still brief" "Shape skill should keep trace concise."
Assert-Contains $shapeSkill "Evaluate intent/shape fit before implementation" "Shape skill should require AI-human evaluation before implementation."

$gateSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-gate\SKILL.md")
Assert-Contains $gateSkill "AI provides evidence and recommendations; the human owns validation" "Gate skill should make human validation ownership explicit."

$codexManifest = Get-Content -Raw -LiteralPath (Join-Path $root ".codex-plugin\plugin.json")
Assert-Contains $codexManifest ".codev.md" "Codex manifest should describe v0.2 single-file state."
Assert-Contains $codexManifest "shape/gate/drift" "Codex manifest should describe lightweight v0.2 skills."
if ($codexManifest -like "*requirements, architecture, roadmap, trace, drift control*") {
    throw "Codex manifest still uses v0.1 heavy-document wording."
}

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("codev-v02-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
Set-Content -LiteralPath (Join-Path $fixture ".codev.md") -Value @"
# CO-DEV

Gate: ultra
Ceremony: light
Current gate: gate-001
Decision: pending

## Intent
Test fixture.
"@

$script = Join-Path $root "scripts\codev-check-gate.ps1"
$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $fixture 2>&1
Assert-Equal $LASTEXITCODE 1 "Pending non-free gate should block."
Assert-Contains ($output | Out-String) "Human approval missing" "Pending gate output"

Set-Content -LiteralPath (Join-Path $fixture ".codev.md") -Value @"
# CO-DEV

Gate: ultra
Ceremony: light
Current gate: gate-001
Decision: approved

## Intent
Test fixture.
"@

$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $fixture 2>&1
Assert-Equal $LASTEXITCODE 0 "Approved gate should pass."
Assert-Contains ($output | Out-String) "Human approval present" "Approved gate output"

Write-Output "CO-DEV v0.2 structure tests passed."

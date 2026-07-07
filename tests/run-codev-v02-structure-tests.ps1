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
Assert-Contains $readme "Before editing a real project" "README should document project binding before implementation."
Assert-Contains $readme "Execution Engine" "README should document multi-skill execution engines."
Assert-Contains $readme "Other skills can improve execution, but they cannot bypass CO-DEV gates" "README should make CO-DEV the governance layer over execution skills."

$shapeSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-shape\SKILL.md")
Assert-Contains $shapeSkill "Roadmap/shape is big-picture and coarse-grained" "Shape skill should prevent roadmap task logs."
Assert-Contains $shapeSkill "Trace is small and fine-grained, but still brief" "Shape skill should keep trace concise."
Assert-Contains $shapeSkill "Evaluate intent/shape fit before implementation" "Shape skill should require AI-human evaluation before implementation."
Assert-Contains $shapeSkill "Execution engine records which development skill or tool layer is allowed to help implementation" "Shape skill should capture the execution layer without making it the gate owner."

$usingSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\using-codev\SKILL.md")
Assert-Contains $usingSkill "Before any code edit in a real project" "Using skill should bind CO-DEV to the active project before code edits."
Assert-Contains $usingSkill "Do not treat tests, builds, or installs as a replacement for the human gate" "Using skill should not let engineering verification replace human review."
Assert-Contains $usingSkill "append one short Trace line" "Using skill should require lightweight trace after implementation work."
Assert-Contains $usingSkill "present a light gate packet" "Using skill should require a human review packet at gate boundaries."
Assert-Contains $usingSkill "CO-DEV is the governance layer, not the only execution skill" "Using skill should explicitly support multi-skill composition."
Assert-Contains $usingSkill "Other skills may be used for engineering execution" "Using skill should allow execution skills."
Assert-Contains $usingSkill "They cannot advance, skip, downgrade, or satisfy a CO-DEV gate" "Using skill should prevent other skills from bypassing CO-DEV."

$gateSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-gate\SKILL.md")
Assert-Contains $gateSkill "AI provides evidence and recommendations; the human owns validation" "Gate skill should make human validation ownership explicit."
Assert-Contains $gateSkill "A gate packet must name the thing the human should experience" "Gate skill should force concrete human inspection."
Assert-Contains $gateSkill "Execution skills cannot close this gate" "Gate skill should prevent execution skills from satisfying human approval."
Assert-Contains $gateSkill "Single-letter y means yep/approved" "Gate skill should accept compact human approval."

$codexManifest = Get-Content -Raw -LiteralPath (Join-Path $root ".codex-plugin\plugin.json")
Assert-Contains $codexManifest ".codev.md" "Codex manifest should describe v0.2 single-file state."
Assert-Contains $codexManifest "shape/gate/drift" "Codex manifest should describe lightweight v0.2 skills."
Assert-Contains $codexManifest "composes with execution skills" "Codex manifest should advertise multi-skill support."
if ($codexManifest -like "*requirements, architecture, roadmap, trace, drift control*") {
    throw "Codex manifest still uses v0.1 heavy-document wording."
}

$template = Get-Content -Raw -LiteralPath (Join-Path $root "templates\codev.md")
Assert-Contains $template "Execution engine:" "Template should include execution engine state."

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
Decision: y

## Intent
Test fixture.
"@

$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $fixture 2>&1
Assert-Equal $LASTEXITCODE 0 "Compact approval should pass."
Assert-Contains ($output | Out-String) "Human approval present" "Approved gate output"

Write-Output "CO-DEV v0.2 structure tests passed."

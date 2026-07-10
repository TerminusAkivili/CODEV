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
Assert-Contains $readme "Gate boundaries are product validation boundaries, not paperwork boundaries" "README should prevent bureaucratic normal gates."
Assert-Contains $readme "A demonstrable batch of related functionality" "README should define normal gates as demonstrable functionality batches."
Assert-Contains $readme "Before editing a real project" "README should document project binding before implementation."
Assert-Contains $readme "Execution Engine" "README should document multi-skill execution engines."
Assert-Contains $readme "Other skills can improve execution, but they cannot bypass CO-DEV gates" "README should make CO-DEV the governance layer over execution skills."
Assert-Contains $readme "CodeV is the governance layer" "README should explain CodeV as governance rather than execution."
Assert-Contains $readme "CodeV manages direction" "README should explain CodeV owns intent, batch, and review timing."
Assert-Contains $readme "Superpowers / Codex manage execution" "README should explain execution layers remain separate."
Assert-Contains $readme "Humans own approval" "README should explain tests/builds are evidence, not approval."
Assert-Contains $readme "Project Architecture" "README should include the CodeV project architecture."
Assert-Contains $readme "Typical Workflow" "README should describe the CodeV workflow order."
Assert-Contains $readme "CodeV = governance layer" "README should summarize the CodeV/Superpowers relationship."
Assert-Contains $readme "First CodeV: read .codev.md + using-codev" "README should document the correct execution order."

$shapeSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-shape\SKILL.md")
Assert-Contains $shapeSkill "Roadmap/shape is big-picture and coarse-grained" "Shape skill should prevent roadmap task logs."
Assert-Contains $shapeSkill "Trace is small and fine-grained, but still brief" "Shape skill should keep trace concise."
Assert-Contains $shapeSkill "Evaluate intent/shape fit before implementation" "Shape skill should require AI-human evaluation before implementation."
Assert-Contains $shapeSkill "Execution engine records which development skill or tool layer is allowed to help implementation" "Shape skill should capture the execution layer without making it the gate owner."
Assert-Contains $shapeSkill "set the next gate at a demonstrable functionality batch" "Shape skill should not place normal gates on internal implementation details."

$usingSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\using-codev\SKILL.md")
Assert-Contains $usingSkill "If the human asks to start, use, enable, or launch CodeV" "Using skill should explicitly trigger when the human names CodeV."
Assert-Contains $usingSkill "load `.codev.md` and this `using-codev` skill before any other execution workflow" "Using skill should require explicit project-state and skill loading before execution skills."
Assert-Contains $usingSkill "Treat CodeV like an active project rule layer, not ambient memory" "Using skill should prevent relying on prior conversation memory for CodeV."
Assert-Contains $usingSkill "Before any code edit in a real project" "Using skill should bind CO-DEV to the active project before code edits."
Assert-Contains $usingSkill "Do not treat tests, builds, or installs as a replacement for the human gate" "Using skill should not let engineering verification replace human review."
Assert-Contains $usingSkill "append one short Trace line" "Using skill should require lightweight trace after implementation work."
Assert-Contains $usingSkill "present a light gate packet" "Using skill should require a human review packet at gate boundaries."
Assert-Contains $usingSkill "CO-DEV is the governance layer, not the only execution skill" "Using skill should explicitly support multi-skill composition."
Assert-Contains $usingSkill "Other skills may be used for engineering execution" "Using skill should allow execution skills."
Assert-Contains $usingSkill "They cannot advance, skip, downgrade, or satisfy a CO-DEV gate" "Using skill should prevent other skills from bypassing CO-DEV."
Assert-Contains $usingSkill "the boundary is a demonstrable functionality batch" "Using skill should define normal gates as product validation boundaries."

$gateSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-gate\SKILL.md")
Assert-Contains $gateSkill "AI provides evidence and recommendations; the human owns validation" "Gate skill should make human validation ownership explicit."
Assert-Contains $gateSkill "A gate packet must name the thing the human should experience" "Gate skill should force concrete human inspection."
Assert-Contains $gateSkill "Execution skills cannot close this gate" "Gate skill should prevent execution skills from satisfying human approval."
Assert-Contains $gateSkill "Single-letter y means yep/approved" "Gate skill should accept compact human approval."
Assert-Contains $gateSkill "Do not block on ordinary functions, helpers, interfaces, or refactors" "Gate skill should prevent bureaucratic normal gate blocking."

$codexManifest = Get-Content -Raw -LiteralPath (Join-Path $root ".codex-plugin\plugin.json")
Assert-Contains $codexManifest ".codev.md" "Codex manifest should describe v0.2 single-file state."
Assert-Contains $codexManifest "shape/gate/drift" "Codex manifest should describe lightweight v0.2 skills."
Assert-Contains $codexManifest "composes with execution skills" "Codex manifest should advertise multi-skill support."
if ($codexManifest -like "*requirements, architecture, roadmap, trace, drift control*") {
    throw "Codex manifest still uses v0.1 heavy-document wording."
}

$template = Get-Content -Raw -LiteralPath (Join-Path $root "templates\codev.md")
Assert-Contains $template "Execution engine:" "Template should include execution engine state."

$ciWorkflow = Get-Content -Raw -LiteralPath (Join-Path $root ".github\workflows\codev-ci.yml")
Assert-Contains $ciWorkflow "pull_request:" "GitHub CI should run on pull requests."
Assert-Contains $ciWorkflow "push:" "GitHub CI should run on pushes."
Assert-Contains $ciWorkflow "run-codev-v02-structure-tests.ps1" "GitHub CI should run structure tests."
Assert-Contains $ciWorkflow "run-codev-check-gate-tests.ps1" "GitHub CI should run gate tests."

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("codev-v02-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
Set-Content -LiteralPath (Join-Path $fixture ".codev.md") -Value @"
# CO-DEV

Gate: ultra
Ceremony: light
Execution engine: superpower
Current gate: gate-001
Decision: pending
Decision gate: gate-001

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
Execution engine: superpower
Current gate: gate-001
Decision: y
Decision gate: gate-001

## Intent
Test fixture.
"@

$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $fixture 2>&1
Assert-Equal $LASTEXITCODE 0 "Compact approval should pass."
Assert-Contains ($output | Out-String) "Human approval present" "Approved gate output"

Write-Output "CO-DEV v0.2 structure tests passed."

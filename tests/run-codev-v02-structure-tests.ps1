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
    if ($Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "$Message Missing '$Needle'."
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if ($Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "$Message Unexpected '$Needle'."
    }
}

function Assert-ContainsCount {
    param([string]$Text, [string]$Needle, [int]$ExpectedCount, [string]$Message)
    $actualCount = ([regex]::Matches($Text, [regex]::Escape($Needle), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    if ($actualCount -ne $ExpectedCount) {
        throw "$Message Expected '$Needle' $ExpectedCount times but found $actualCount."
    }
}

function Get-PowerShellExecutable {
    if ($PSVersionTable.PSEdition -eq "Core") {
        return (Get-Process -Id $PID).Path
    }
    return (Join-Path $PSHOME "powershell.exe")
}

$expectedSkills = @(
    "using-codev",
    "codev-shape",
    "codev-gate",
    "codev-drift"
)

$skillDirs = Get-ChildItem -LiteralPath (Join-Path $root "skills") -Directory | Select-Object -ExpandProperty Name | Sort-Object
Assert-Equal ($skillDirs -join ",") (($expectedSkills | Sort-Object) -join ",") "Skill set should be lightweight v0.3."

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
Assert-Contains $readme "six required metadata fields" "README should document the complete v0.3 state."
Assert-Contains $readme "Decision gate" "README examples should include the decision gate."
Assert-Contains $readme "Decision gate must exactly match Current gate" "README should document exact gate binding."
Assert-Contains $readme "pwsh -File scripts/codev.ps1 check -ProjectRoot ." "README should document the canonical check command."
Assert-Contains $readme "pwsh -File scripts/codev.ps1 status -ProjectRoot ." "README should document the canonical status command."
Assert-Contains $readme "pwsh -File scripts/codev.ps1 approve -ProjectRoot . -GateId gate-id" "README should document the canonical approve command."
Assert-Contains $readme "Windows PowerShell 5.1" "README should document Windows PowerShell compatibility."
Assert-Contains $readme "macOS and Linux require PowerShell 7" "README should document the cross-platform prerequisite."
Assert-Contains $readme "Pre-v0.3 migration" "README should document migration from older state files."
Assert-Contains $readme "transactional approval" "README should document approval write integrity."
Assert-Contains $readme "preserves the supported original encoding and BOM" "README should document encoding preservation."
Assert-Contains $readme "new unmarked state files and the default template remain UTF-8 without BOM" "README should document the default encoding."
Assert-Contains $readme "v0.3 gate tests cover six-field validation" "README should state the complete gate test validation scope."
Assert-Contains $readme "exact case-sensitive Decision gate binding" "README should state the gate binding proof."
Assert-Contains $readme "approval transitions" "README should state the approval transition proof."
Assert-Contains $readme "transactional encoding/BOM preservation" "README should state the approval write preservation proof."

$shapeSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-shape\SKILL.md")
Assert-Contains $shapeSkill "Roadmap/shape is big-picture and coarse-grained" "Shape skill should prevent roadmap task logs."
Assert-Contains $shapeSkill "Trace is small and fine-grained, but still brief" "Shape skill should keep trace concise."
Assert-Contains $shapeSkill "Evaluate intent/shape fit before implementation" "Shape skill should require AI-human evaluation before implementation."
Assert-Contains $shapeSkill "Execution engine records which development skill or tool layer is allowed to help implementation" "Shape skill should capture the execution layer without making it the gate owner."
Assert-Contains $shapeSkill "set the next gate at a demonstrable functionality batch" "Shape skill should not place normal gates on internal implementation details."
Assert-Contains $shapeSkill "Decision gate: none" "Shape skill default state should include the decision gate."
Assert-Contains $shapeSkill 'new gate means `Decision: pending` plus the matching `Decision gate`' "Shape skill should bind newly created gates."
Assert-Contains $shapeSkill 'no gate means `Decision: pending` plus `Decision gate: none`' "Shape skill should clear decision binding when no gate exists."

$usingSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\using-codev\SKILL.md")
Assert-Contains $usingSkill "If the human asks to start, use, enable, or launch CodeV" "Using skill should explicitly trigger when the human names CodeV."
Assert-Contains $usingSkill 'load `.codev.md` and this `using-codev` skill before any other execution workflow' "Using skill should require explicit project-state and skill loading before execution skills."
Assert-Contains $usingSkill "Treat CodeV like an active project rule layer, not ambient memory" "Using skill should prevent relying on prior conversation memory for CodeV."
Assert-Contains $usingSkill "Before any code edit in a real project" "Using skill should bind CO-DEV to the active project before code edits."
Assert-Contains $usingSkill "Do not treat tests, builds, or installs as a replacement for the human gate" "Using skill should not let engineering verification replace human review."
Assert-Contains $usingSkill "append one short Trace line" "Using skill should require lightweight trace after implementation work."
Assert-Contains $usingSkill "present a light gate packet" "Using skill should require a human review packet at gate boundaries."
Assert-Contains $usingSkill "CO-DEV is the governance layer, not the only execution skill" "Using skill should explicitly support multi-skill composition."
Assert-Contains $usingSkill "Other skills may be used for engineering execution" "Using skill should allow execution skills."
Assert-Contains $usingSkill "They cannot advance, skip, downgrade, or satisfy a CO-DEV gate" "Using skill should prevent other skills from bypassing CO-DEV."
Assert-Contains $usingSkill "the boundary is a demonstrable functionality batch" "Using skill should define normal gates as product validation boundaries."
Assert-Contains $usingSkill '- `Decision gate: none|gate-id`' "Using skill should require the sixth metadata field."
Assert-Contains $usingSkill "Decision gate must exactly match Current gate" "Using skill should document exact gate binding."
Assert-Contains $usingSkill 'new gate means `Decision: pending` plus the matching `Decision gate`' "Using skill should define new-gate state."
Assert-Contains $usingSkill 'no gate means `Decision: pending` plus `Decision gate: none`' "Using skill should define no-gate state."

$gateSkill = Get-Content -Raw -LiteralPath (Join-Path $root "skills\codev-gate\SKILL.md")
Assert-Contains $gateSkill "AI provides evidence and recommendations; the human owns validation" "Gate skill should make human validation ownership explicit."
Assert-Contains $gateSkill "A gate packet must name the thing the human should experience" "Gate skill should force concrete human inspection."
Assert-Contains $gateSkill "Execution skills cannot close this gate" "Gate skill should prevent execution skills from satisfying human approval."
Assert-Contains $gateSkill "Single-letter y means yep/approved" "Gate skill should accept compact human approval."
Assert-Contains $gateSkill "Do not block on ordinary functions, helpers, interfaces, or refactors" "Gate skill should prevent bureaucratic normal gate blocking."
Assert-Contains $gateSkill "Decision gate must be exactly identical to Current gate" "Gate skill should require exact gate identity."
Assert-Contains $gateSkill "case-sensitive" "Gate skill should explain exact identity comparison."

$codexManifestPath = Join-Path $root ".codex-plugin\plugin.json"
$codexManifest = Get-Content -Raw -LiteralPath $codexManifestPath
Assert-Contains $codexManifest ".codev.md" "Codex manifest should describe v0.3 single-file state."
Assert-Contains $codexManifest "shape/gate/drift" "Codex manifest should describe lightweight v0.3 skills."
Assert-Contains $codexManifest "composes with execution skills" "Codex manifest should advertise multi-skill support."
if ($codexManifest -like "*requirements, architecture, roadmap, trace, drift control*") {
    throw "Codex manifest still uses v0.1 heavy-document wording."
}

$template = Get-Content -Raw -LiteralPath (Join-Path $root "templates\codev.md")
Assert-Contains $template "Execution engine:" "Template should include execution engine state."
Assert-Contains $template "Decision gate: none" "Template should include the default decision gate."

$codexVersion = (Get-Content -Raw -LiteralPath $codexManifestPath | ConvertFrom-Json).version
$claudeVersion = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$cursorVersion = (Get-Content -Raw -LiteralPath (Join-Path $root ".cursor-plugin\plugin.json") | ConvertFrom-Json).version
$marketplaceVersion = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\marketplace.json") | ConvertFrom-Json).plugins[0].version
Assert-Equal $codexVersion "0.3.0" "Codex plugin version should be exactly 0.3.0."
Assert-Equal $claudeVersion "0.3.0" "Claude plugin version should be exactly 0.3.0."
Assert-Equal $cursorVersion "0.3.0" "Cursor plugin version should be exactly 0.3.0."
Assert-Equal $marketplaceVersion "0.3.0" "Marketplace plugin version should be exactly 0.3.0."

$designSpec = Get-Content -Raw -LiteralPath (Join-Path $root "docs\superpowers\specs\2026-07-10-codev-v0.3-integrity-release-design.md")
Assert-Contains $designSpec "preserves supported original encoding and BOM" "Design spec should describe approval encoding preservation."
Assert-Contains $designSpec "unmarked new state files and the default template remain UTF-8 without BOM" "Design spec should retain the unmarked default encoding."

$canonicalCli = Get-Content -Raw -LiteralPath (Join-Path $root "scripts\codev.ps1")
Assert-Contains $canonicalCli "Publish-CodeVBytesAtomically" "Approval should publish through an atomic replacement helper."
Assert-Contains $canonicalCli "Restore-CodeVFileSafely" "Approval recovery should preserve superseding state changes."
Assert-NotContains $canonicalCli ".SetLength(0)" "Approval must not truncate the live state file in place."
Assert-NotContains $canonicalCli "CODEV_TEST_APPROVAL_READY_PATH" "Approval must not expose an arbitrary-file test hook."

$ciWorkflow = Get-Content -Raw -LiteralPath (Join-Path $root ".github\workflows\codev-ci.yml")
Assert-Contains $ciWorkflow "pull_request:" "GitHub CI should run on pull requests."
Assert-Contains $ciWorkflow "push:" "GitHub CI should run on pushes."
Assert-Contains $ciWorkflow "workflow_dispatch:" "GitHub CI should support manual runs."
Assert-Contains $ciWorkflow "contents: read" "GitHub CI should keep read-only repository permissions."
Assert-Contains $ciWorkflow "windows-latest" "GitHub CI should include Windows in the cross-platform matrix."
Assert-Contains $ciWorkflow "ubuntu-latest" "GitHub CI should include Ubuntu in the cross-platform matrix."
Assert-Contains $ciWorkflow "macos-latest" "GitHub CI should include macOS in the cross-platform matrix."
Assert-Contains $ciWorkflow "shell: pwsh" "GitHub CI should use PowerShell 7 for the cross-platform job."
Assert-Contains $ciWorkflow "Windows PowerShell 5.1 compatibility" "GitHub CI should have a separate Windows PowerShell 5.1 compatibility job."
Assert-Contains $ciWorkflow "shell: powershell" "GitHub CI should use Windows PowerShell for the compatibility job."
Assert-ContainsCount $ciWorkflow "run-codev-v02-structure-tests.ps1" 2 "Both GitHub CI jobs should run structure tests."
Assert-ContainsCount $ciWorkflow "run-codev-check-gate-tests.ps1" 2 "Both GitHub CI jobs should run gate tests."
Assert-ContainsCount $ciWorkflow "powershell -NoProfile -ExecutionPolicy Bypass" 2 "The Windows PowerShell compatibility job should invoke both suites explicitly."
Assert-Contains $ciWorkflow "Validate Codex plugin manifest" "GitHub CI should run the official Codex plugin validator."
Assert-Contains $ciWorkflow "validate_plugin.py" "GitHub CI should invoke the Codex plugin validator script."
Assert-Contains $ciWorkflow "actions/setup-python@v5" "GitHub CI should install a supported Python runtime for plugin validation."
Assert-Contains $ciWorkflow "PyYAML>=6,<7" "GitHub CI should install the official validator dependency."
Assert-Contains `
    $ciWorkflow `
    "https://raw.githubusercontent.com/openai/codex/1f0566d3f59298d1bb88820a0d35294f1eeb07ea/" `
    "GitHub CI should pin the validator to an exact official Codex commit."
Assert-Contains `
    $ciWorkflow `
    "codex-rs/skills/src/assets/samples/plugin-creator/scripts/validate_plugin.py" `
    "GitHub CI should download the official plugin-creator validator."

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("codev-v03-" + [guid]::NewGuid().ToString("N"))
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
$powerShellExecutable = Get-PowerShellExecutable
$output = & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $fixture 2>&1
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

$output = & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $fixture 2>&1
Assert-Equal $LASTEXITCODE 0 "Compact approval should pass."
Assert-Contains ($output | Out-String) "Human approval present" "Approved gate output"

Write-Output "CO-DEV v0.3 structure tests passed."

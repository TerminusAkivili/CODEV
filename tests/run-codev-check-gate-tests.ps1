$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$codevScript = Join-Path $root "scripts\codev.ps1"
$legacyScript = Join-Path $root "scripts\codev-check-gate.ps1"

if (-not (Test-Path -LiteralPath $legacyScript)) {
    throw "Missing legacy gate script: $legacyScript"
}

function Get-PowerShellExecutable {
    if ($PSVersionTable.PSEdition -eq "Core") {
        return (Get-Process -Id $PID).Path
    }
    return (Join-Path $PSHOME "powershell.exe")
}

$fixtureDirectories = [System.Collections.Generic.List[string]]::new()

function New-Fixture {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("codev-gate-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $fixtureDirectories.Add($dir)
    return $dir
}

function Invoke-PowerShellChild {
    param([string[]]$Arguments)

    $powerShellExecutable = Get-PowerShellExecutable
    $output = & $powerShellExecutable @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    }
}

function Run-CodeV {
    param(
        [string]$ProjectRoot,
        [ValidateSet("check", "status", "approve")]
        [string]$Command = "check",
        [AllowEmptyString()]
        [string]$GateId
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $codevScript,
        $Command,
        "-ProjectRoot",
        $ProjectRoot
    )
    if ($PSBoundParameters.ContainsKey("GateId")) {
        $arguments += @("-GateId", $GateId)
    }

    return Invoke-PowerShellChild -Arguments $arguments
}

function Run-LegacyGate {
    param(
        [string]$ProjectRoot,
        [switch]$Status
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $legacyScript,
        "-ProjectRoot",
        $ProjectRoot
    )
    if ($Status) {
        $arguments += "-Status"
    }

    return Invoke-PowerShellChild -Arguments $arguments
}

function Write-State {
    param(
        [string]$ProjectRoot,
        [string]$Gate = "normal",
        [string]$Ceremony = "light",
        [string]$ExecutionEngine = "superpower",
        [string]$CurrentGate = "gate-1",
        [string]$Decision = "pending",
        [string]$DecisionGate = $CurrentGate,
        [switch]$OmitGate,
        [switch]$OmitDecisionGate,
        [string[]]$AdditionalPreambleLines = @(),
        [string[]]$IntentLines = @("Fixture."),
        [string]$FirstHeading = "## Intent",
        [string]$NewLine = "`r`n",
        [bool]$TrailingNewLine = $true
    )

    $lines = @("# CO-DEV", "")
    if (-not $OmitGate) {
        $lines += "Gate: $Gate"
    }
    $lines += "Ceremony: $Ceremony"
    $lines += "Execution engine: $ExecutionEngine"
    $lines += "Current gate: $CurrentGate"
    $lines += "Decision: $Decision"
    if (-not $OmitDecisionGate) {
        $lines += "Decision gate: $DecisionGate"
    }
    $lines += $AdditionalPreambleLines
    $lines += ""
    $lines += $FirstHeading
    $lines += $IntentLines

    $content = $lines -join $NewLine
    if ($TrailingNewLine) {
        $content += $NewLine
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $ProjectRoot ".codev.md"), $content, $utf8NoBom)
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if ($Text -notlike "*$Needle*") {
        throw "$Message Missing '$Needle' in: $Text"
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if ($Text -like "*$Needle*") {
        throw "$Message Unexpected '$Needle' in: $Text"
    }
}

function Assert-ByteSequenceEqual {
    param([byte[]]$Actual, [byte[]]$Expected, [string]$Message)

    if ($Actual.Length -ne $Expected.Length) {
        throw "$Message Byte lengths differ. Expected $($Expected.Length) but got $($Actual.Length)."
    }

    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) {
            throw "$Message Byte mismatch at index $index. Expected $($Expected[$index]) but got $($Actual[$index])."
        }
    }
}

function Assert-Utf8WithoutBom {
    param([byte[]]$Bytes, [string]$Message)

    if (
        $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF
    ) {
        throw "$Message UTF-8 BOM was present."
    }

    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $null = $strictUtf8.GetString($Bytes)
}

$tests = @()

$tests += @{
    Name = "stale approval bound to another gate is invalid"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-new" -Decision "approved" -DecisionGate "gate-old"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "A decision bound to another gate is invalid."
        Assert-Contains $result.Output "Decision gate 'gate-old' does not match Current gate 'gate-new'" "Mismatch output"
    }
}

$tests += @{
    Name = "gate binding comparison is case sensitive"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-alpha" -Decision "approved" -DecisionGate "Gate-Alpha"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Decision gate 'Gate-Alpha' does not match Current gate 'gate-alpha'" "Output"
    }
}

$tests += @{
    Name = "missing decision gate is invalid"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -OmitDecisionGate
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Missing 'Decision gate'" "Output"
    }
}

$tests += @{
    Name = "duplicate gate field is invalid"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -AdditionalPreambleLines @("Gate: loose")
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Duplicate 'Gate'" "Output"
    }
}

$tests += @{
    Name = "invalid gate is rejected"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "nonsense"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Invalid Gate 'nonsense'" "Output"
    }
}

$tests += @{
    Name = "invalid ceremony is rejected"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Ceremony "nonsense"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Invalid Ceremony 'nonsense'" "Output"
    }
}

$tests += @{
    Name = "invalid execution engine is rejected"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -ExecutionEngine "nonsense"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Invalid Execution engine 'nonsense'" "Output"
    }
}

$tests += @{
    Name = "invalid decision is rejected"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Decision "nonsense"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Invalid Decision 'nonsense'" "Output"
    }
}

$tests += @{
    Name = "no current gate cannot be approved"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "none" -Decision "approved" -DecisionGate "none"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Decision must be 'pending' when Current gate is 'none'" "Output"
    }
}

$tests += @{
    Name = "no current gate cannot retain a decision gate"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "none" -Decision "pending" -DecisionGate "gate-old"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Decision gate must be 'none' when Current gate is 'none'" "Output"
    }
}

$tests += @{
    Name = "free mode still rejects stale decision binding"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "free" -CurrentGate "gate-new" -Decision "pending" -DecisionGate "gate-old"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Decision gate 'gate-old' does not match Current gate 'gate-new'" "Output"
    }
}

$tests += @{
    Name = "status rejects malformed state"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -OmitGate
        $result = Run-CodeV -ProjectRoot $dir -Command "status"
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Missing 'Gate'" "Output"
        Assert-NotContains $result.Output "CO-DEV status" "Status output"
    }
}

$tests += @{
    Name = "metadata fields after any level-two heading are ignored"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Decision "approved" -FirstHeading "## Shape" -IntentLines @(
            "Fixture.",
            "Gate: nonsense",
            "Ceremony: nonsense",
            "Execution engine: nonsense",
            "Current gate: gate-other",
            "Decision: rejected",
            "Decision gate: gate-other",
            "## Trace",
            "Decision: redirected"
        )
        $result = Run-CodeV -ProjectRoot $dir -Command "status"
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Gate: normal" "Gate output"
        Assert-Contains $result.Output "Decision: approved" "Decision output"
        Assert-NotContains $result.Output "Gate: nonsense" "Preamble isolation"
        Assert-NotContains $result.Output "gate-other" "Preamble isolation"
    }
}

$tests += @{
    Name = "approve requires a gate id"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-required" -Decision "pending" -DecisionGate "gate-required"
        $statePath = Join-Path $dir ".codev.md"
        $before = [System.IO.File]::ReadAllBytes($statePath)
        $result = Run-CodeV -ProjectRoot $dir -Command "approve"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "GateId is required for approve" "Output"
        Assert-ByteSequenceEqual $after $before "Missing GateId must not change the state file."
    }
}

$tests += @{
    Name = "approve rejects a different gate id without changing bytes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-current" -Decision "pending" -DecisionGate "gate-current"
        $statePath = Join-Path $dir ".codev.md"
        $before = [System.IO.File]::ReadAllBytes($statePath)
        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-other"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "GateId 'gate-other' does not exactly match Current gate 'gate-current'" "Output"
        Assert-ByteSequenceEqual $after $before "Mismatched GateId must not change the state file."
    }
}

$tests += @{
    Name = "approve gate id comparison is case sensitive and preserves bytes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-alpha" -Decision "pending" -DecisionGate "gate-alpha"
        $statePath = Join-Path $dir ".codev.md"
        $before = [System.IO.File]::ReadAllBytes($statePath)
        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "Gate-Alpha"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "GateId 'Gate-Alpha' does not exactly match Current gate 'gate-alpha'" "Output"
        Assert-ByteSequenceEqual $after $before "Case-mismatched GateId must not change the state file."
    }
}

$tests += @{
    Name = "approve cannot record a decision when current gate is none"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "none" -Decision "pending" -DecisionGate "none"
        $statePath = Join-Path $dir ".codev.md"
        $before = [System.IO.File]::ReadAllBytes($statePath)
        $result = Run-CodeV -ProjectRoot $dir -Command "approve"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Current gate is 'none'; there is no active gate to approve" "Output"
        Assert-ByteSequenceEqual $after $before "No-active-gate approval must not change the state file."
    }
}

$tests += @{
    Name = "approve updates only approval metadata and preserves CRLF document content"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $newline = "`r`n"
        $beforeText = @(
            "# CO-DEV",
            "",
            "Gate: strict",
            "Ceremony: audit",
            "Execution engine: custom:runner",
            "Current gate: Gate-Exact",
            "Decision: rejected",
            "Decision gate :   Gate-Exact   ",
            "Unrelated preamble: keep exactly",
            "",
            "## Intent",
            "Keep intent text.",
            "## Shape",
            "Keep shape text.",
            "## Trace",
            "Keep trace text."
        ) -join $newline
        $beforeText += $newline
        [System.IO.File]::WriteAllText($statePath, $beforeText, [System.Text.UTF8Encoding]::new($false))

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "Gate-Exact"
        $afterText = [System.IO.File]::ReadAllText($statePath)
        $expectedText = $beforeText.Replace(
            "Decision: rejected$newline",
            "Decision: approved$newline"
        ).Replace(
            "Decision gate :   Gate-Exact   $newline",
            "Decision gate: Gate-Exact$newline"
        )

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval recorded for gate Gate-Exact." "Output"
        Assert-Equal $afterText $expectedText "Only Decision and Decision gate lines should change."
        Assert-Contains $afterText "## Intent${newline}Keep intent text." "Intent preservation"
        Assert-Contains $afterText "## Shape${newline}Keep shape text." "Shape preservation"
        Assert-Contains $afterText "## Trace${newline}Keep trace text." "Trace preservation"
        Assert-Contains $afterText "Unrelated preamble: keep exactly" "Unrelated text preservation"
        Assert-Equal ([regex]::Matches($afterText, "(?<!`r)`n").Count) 0 "CRLF newline preservation"
    }
}

$tests += @{
    Name = "approve preserves LF without trailing newline and writes UTF-8 without BOM"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $unicodeText = "caf$([char]0x00E9)"
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-lf" `
            -Decision "pending" `
            -DecisionGate "gate-lf" `
            -AdditionalPreambleLines @("Unrelated: $unicodeText") `
            -IntentLines @("Keep $unicodeText.") `
            -NewLine "`n" `
            -TrailingNewLine $false

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-lf"
        $bytes = [System.IO.File]::ReadAllBytes($statePath)
        $afterText = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval recorded for gate gate-lf." "Output"
        Assert-Contains $afterText "Decision: approved" "Decision update"
        Assert-Contains $afterText "Decision gate: gate-lf" "Decision gate update"
        Assert-Contains $afterText "Unrelated: $unicodeText" "UTF-8 unrelated text preservation"
        Assert-Contains $afterText "Keep $unicodeText." "UTF-8 body preservation"
        Assert-Equal $afterText.Contains("`r") $false "LF newline preservation"
        Assert-Equal $afterText.EndsWith("`n") $false "Trailing newline preservation"
        Assert-Utf8WithoutBom $bytes "Approved state file"
    }
}

$tests += @{
    Name = "matching approved decision passes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -CurrentGate "gate-1" -Decision "approved" -DecisionGate "gate-1"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval present" "Output"
    }
}

$tests += @{
    Name = "matching compact y decision passes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -CurrentGate "gate-1" -Decision "y" -DecisionGate "gate-1"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval present" "Output"
    }
}

$tests += @{
    Name = "matching pending decision blocks continuation"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -CurrentGate "gate-1" -Decision "pending" -DecisionGate "gate-1"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 1 "Exit code"
        Assert-Contains $result.Output "Human approval missing" "Output"
    }
}

$tests += @{
    Name = "no current gate with pending decision passes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "ultra" -CurrentGate "none" -Decision "pending" -DecisionGate "none"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "No current gate" "Output"
    }
}

$tests += @{
    Name = "free mode with valid binding passes with warning"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "free" -CurrentGate "gate-1" -Decision "pending" -DecisionGate "gate-1"
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Low-assurance mode" "Output"
    }
}

$tests += @{
    Name = "missing state is invalid"
    Run = {
        $dir = New-Fixture
        $result = Run-CodeV -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Missing CO-DEV state" "Output"
    }
}

$tests += @{
    Name = "status prints all six fields"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "normal" -Ceremony "light" -ExecutionEngine "superpower" -CurrentGate "gate-status" -Decision "pending" -DecisionGate "gate-status"
        $result = Run-CodeV -ProjectRoot $dir -Command "status"
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "CO-DEV status" "Output"
        Assert-Contains $result.Output "Gate: normal" "Output"
        Assert-Contains $result.Output "Ceremony: light" "Output"
        Assert-Contains $result.Output "Execution engine: superpower" "Output"
        Assert-Contains $result.Output "Current gate: gate-status" "Output"
        Assert-Contains $result.Output "Decision: pending" "Output"
        Assert-Contains $result.Output "Decision gate: gate-status" "Output"
    }
}

$tests += @{
    Name = "project root path with spaces is preserved"
    Run = {
        $fixtureRoot = New-Fixture
        $dir = Join-Path $fixtureRoot "project root with spaces"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-State -ProjectRoot $dir -Gate "normal" -CurrentGate "gate-spaces" -Decision "pending" -DecisionGate "gate-spaces"
        $result = Run-CodeV -ProjectRoot $dir -Command "status"
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Current gate: gate-spaces" "Output"
    }
}

$tests += @{
    Name = "legacy checker remains callable"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -CurrentGate "gate-legacy" -Decision "approved" -DecisionGate "gate-legacy"
        $result = Run-LegacyGate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval present" "Output"
    }
}

$passed = 0
try {
    foreach ($test in $tests) {
        & $test.Run
        Write-Output "PASS $($test.Name)"
        $passed++
    }

    Write-Output "All $passed CO-DEV gate tests passed."
} finally {
    foreach ($fixtureDirectory in $fixtureDirectories) {
        Remove-Item -LiteralPath $fixtureDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

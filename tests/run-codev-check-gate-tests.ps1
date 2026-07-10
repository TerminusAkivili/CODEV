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
        [string]$StatePath,
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
    if ($PSBoundParameters.ContainsKey("StatePath")) {
        $arguments += @("-StatePath", $StatePath)
    }

    return Invoke-PowerShellChild -Arguments $arguments
}

function Run-LegacyGate {
    param(
        [string]$ProjectRoot,
        [string]$StatePath,
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
    if ($PSBoundParameters.ContainsKey("StatePath")) {
        $arguments += @("-StatePath", $StatePath)
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

function Assert-CommandParity {
    param(
        $Canonical,
        $Legacy,
        [int]$ExpectedExitCode,
        [string[]]$KeyOutput,
        [string]$Message
    )

    Assert-Equal $Canonical.ExitCode $ExpectedExitCode "$Message canonical exit code"
    Assert-Equal $Legacy.ExitCode $ExpectedExitCode "$Message legacy exit code"
    Assert-Equal $Legacy.ExitCode $Canonical.ExitCode "$Message matching exit codes"
    foreach ($needle in $KeyOutput) {
        Assert-Contains $Canonical.Output $needle "$Message canonical output"
        Assert-Contains $Legacy.Output $needle "$Message legacy output"
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

function Get-EncodedBytes {
    param(
        [string]$Text,
        [Parameter(Mandatory = $true)][System.Text.Encoding]$Encoding,
        [switch]$IncludePreamble
    )

    [byte[]]$body = $Encoding.GetBytes($Text)
    [byte[]]$preamble = @()
    if ($IncludePreamble) {
        $preamble = $Encoding.GetPreamble()
    }

    [byte[]]$bytes = New-Object byte[] ($preamble.Length + $body.Length)
    if ($preamble.Length -gt 0) {
        [System.Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
    }
    if ($body.Length -gt 0) {
        [System.Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
    }

    return $bytes
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
        Assert-Contains `
            $result.Output `
            "Missing 'Decision gate' in .codev.md. Set it to 'none' or the active Current gate." `
            "Migration output"
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
    Name = "metadata fields inside a fenced preamble example are ignored"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $content = @(
            "# CO-DEV",
            "",
            '```text',
            "Gate: free",
            "Ceremony: light",
            "Execution engine: superpower",
            "Current gate: gate-fenced",
            "Decision: pending",
            "Decision gate: gate-fenced",
            '```',
            "",
            "## Intent",
            "Fixture."
        ) -join "`n"
        [System.IO.File]::WriteAllText(
            $statePath,
            $content,
            [System.Text.UTF8Encoding]::new($false)
        )

        $result = Run-CodeV -ProjectRoot $dir -Command "status"

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Missing 'Gate' in .codev.md." "Output"
        Assert-NotContains $result.Output "CO-DEV status" "Status output"
    }
}

$tests += @{
    Name = "an indented level-two heading ends the metadata preamble"
    Run = {
        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -OmitDecisionGate `
            -FirstHeading "   ## Intent" `
            -IntentLines @(
                "Decision gate: gate-1",
                "Fixture."
            )

        $result = Run-CodeV -ProjectRoot $dir -Command "status"

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains `
            $result.Output `
            "Missing 'Decision gate' in .codev.md. Set it to 'none' or the active Current gate." `
            "Output"
        Assert-NotContains $result.Output "CO-DEV status" "Status output"
    }
}

$tests += @{
    Name = "a Setext level-two heading ends the metadata preamble"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $content = @(
            "# CO-DEV",
            "",
            "Gate: normal",
            "Ceremony: light",
            "Execution engine: superpower",
            "Current gate: gate-setext",
            "Decision: pending",
            "",
            "Intent",
            "------",
            "Decision gate: gate-setext",
            "Fixture."
        ) -join "`n"
        [System.IO.File]::WriteAllText(
            $statePath,
            $content,
            [System.Text.UTF8Encoding]::new($false)
        )

        $result = Run-CodeV -ProjectRoot $dir -Command "status"

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains `
            $result.Output `
            "Missing 'Decision gate' in .codev.md. Set it to 'none' or the active Current gate." `
            "Output"
        Assert-NotContains $result.Output "CO-DEV status" "Status output"
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
    Name = "approve command dispatch is case insensitive"
    Run = {
        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-command-case" `
            -Decision "pending" `
            -DecisionGate "gate-command-case"

        $result = Run-CodeV `
            -ProjectRoot $dir `
            -Command "Approve" `
            -GateId "gate-command-case"
        $after = [System.IO.File]::ReadAllText((Join-Path $dir ".codev.md"))

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains `
            $result.Output `
            "Human approval recorded for gate gate-command-case." `
            "Output"
        Assert-Contains $after "Decision: approved" "Decision update"
    }
}

$tests += @{
    Name = "approve ignores the obsolete arbitrary ready path environment variable"
    Run = {
        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-ready-env" `
            -Decision "pending" `
            -DecisionGate "gate-ready-env"
        $victimPath = Join-Path $dir "victim.txt"
        [System.IO.File]::WriteAllText($victimPath, "keep this content")

        $previousReadyPath = $env:CODEV_TEST_APPROVAL_READY_PATH
        $env:CODEV_TEST_APPROVAL_READY_PATH = $victimPath
        try {
            $result = Run-CodeV `
                -ProjectRoot $dir `
                -Command "approve" `
                -GateId "gate-ready-env"
        } finally {
            $env:CODEV_TEST_APPROVAL_READY_PATH = $previousReadyPath
        }

        $victimContent = [System.IO.File]::ReadAllText($victimPath)
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Equal $victimContent "keep this content" "Victim file content"
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
    Name = "approve fails without modification while the state file is exclusively locked"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-locked" -Decision "pending" -DecisionGate "gate-locked"
        $statePath = Join-Path $dir ".codev.md"
        $before = [System.IO.File]::ReadAllBytes($statePath)
        $lock = [System.IO.File]::Open(
            $statePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        try {
            $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-locked"
        } finally {
            $lock.Dispose()
        }
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-ByteSequenceEqual $after $before "Locked approval must not change the state file."
    }
}

$tests += @{
    Name = "approve does not overwrite a concurrent state change"
    Run = {
        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-race" `
            -Decision "pending" `
            -DecisionGate "gate-race" `
            -IntentLines @("Original intent.")
        $statePath = Join-Path $dir ".codev.md"
        $powerShellExecutable = Get-PowerShellExecutable
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $codevScript,
            "approve",
            "-ProjectRoot",
            $dir,
            "-GateId",
            "gate-race"
        )

        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $powerShellExecutable
        $processInfo.Arguments = $arguments -join " "
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        if ($PSVersionTable.PSEdition -eq "Core") {
            $processInfo.Environment["CODEV_TEST_APPROVAL_DELAY_MS"] = "2000"
        } else {
            $processInfo.EnvironmentVariables["CODEV_TEST_APPROVAL_DELAY_MS"] = "2000"
        }
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $null = $process.Start()

        $tempPattern = "." + [System.IO.Path]::GetFileName($statePath) + ".codev-*.tmp"
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        $tempFile = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $tempFile = Get-ChildItem `
                -LiteralPath $dir `
                -Filter $tempPattern `
                -File `
                -Force `
                -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $tempFile) {
                break
            }
            if ($process.HasExited) {
                break
            }
            Start-Sleep -Milliseconds 20
        }

        if ($null -eq $tempFile) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Approval process did not reach the pre-publication test point."
        }

        $concurrentEditCompleted = $false
        $editDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $concurrentEditCompleted -and [DateTime]::UtcNow -lt $editDeadline) {
            try {
                $concurrentText = [System.IO.File]::ReadAllText($statePath).
                    Replace("Current gate: gate-race", "Current gate: gate-concurrent").
                    Replace("Decision gate: gate-race", "Decision gate: gate-concurrent").
                    Replace("Original intent.", "Concurrent intent.")
                [System.IO.File]::WriteAllText(
                    $statePath,
                    $concurrentText,
                    [System.Text.UTF8Encoding]::new($false)
                )
                $concurrentEditCompleted = $true
            } catch [System.IO.IOException] {
                Start-Sleep -Milliseconds 20
            }
        }

        if (-not $concurrentEditCompleted) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Concurrent state edit could not complete."
        }

        $process.WaitForExit()
        $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $exitCode = $process.ExitCode
        $after = [System.IO.File]::ReadAllText($statePath)

        Assert-Equal $exitCode 2 "Exit code"
        Assert-Contains $output "State changed during approval" "Output"
        Assert-Contains $after "Current gate: gate-concurrent" "Concurrent gate preservation"
        Assert-Contains $after "Decision gate: gate-concurrent" "Concurrent binding preservation"
        Assert-Contains $after "Concurrent intent." "Concurrent content preservation"
        Assert-NotContains $after "Decision: approved" "Approval must not overwrite concurrent state"
    }
}

$tests += @{
    Name = "approval recovery preserves an edit completed during rollback"
    Run = {
        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-recovery-a" `
            -Decision "pending" `
            -DecisionGate "gate-recovery-a" `
            -IntentLines @("Original recovery intent.")
        $statePath = Join-Path $dir ".codev.md"
        $originalText = [System.IO.File]::ReadAllText($statePath)
        $editB = $originalText.
            Replace("gate-recovery-a", "gate-recovery-b").
            Replace("Original recovery intent.", "Recovery edit B.")
        $editC = $editB.
            Replace("gate-recovery-b", "gate-recovery-c").
            Replace("Recovery edit B.", "Recovery edit C.")

        $powerShellExecutable = Get-PowerShellExecutable
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $codevScript,
            "approve",
            "-ProjectRoot",
            $dir,
            "-GateId",
            "gate-recovery-a"
        )
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $powerShellExecutable
        $processInfo.Arguments = $arguments -join " "
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        if ($PSVersionTable.PSEdition -eq "Core") {
            $processInfo.Environment["CODEV_TEST_APPROVAL_DELAY_MS"] = "2000"
            $processInfo.Environment["CODEV_TEST_APPROVAL_RECOVERY_DELAY_MS"] = "2000"
        } else {
            $processInfo.EnvironmentVariables["CODEV_TEST_APPROVAL_DELAY_MS"] = "2000"
            $processInfo.EnvironmentVariables["CODEV_TEST_APPROVAL_RECOVERY_DELAY_MS"] = "2000"
        }
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $null = $process.Start()

        $tempPattern = "." + [System.IO.Path]::GetFileName($statePath) + ".codev-*.tmp"
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        $tempFile = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $tempFile = Get-ChildItem `
                -LiteralPath $dir `
                -Filter $tempPattern `
                -File `
                -Force `
                -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $tempFile) {
                break
            }
            if ($process.HasExited) {
                break
            }
            Start-Sleep -Milliseconds 20
        }
        if ($null -eq $tempFile) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Approval process did not pause before recovery race setup."
        }

        [System.IO.File]::WriteAllText(
            $statePath,
            $editB,
            [System.Text.UTF8Encoding]::new($false)
        )

        $approvedStateVisible = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                $currentText = [System.IO.File]::ReadAllText($statePath)
                if ($currentText -like "*Decision: approved*") {
                    $approvedStateVisible = $true
                    break
                }
            } catch [System.IO.IOException] {
            }
            if ($process.HasExited) {
                break
            }
            Start-Sleep -Milliseconds 20
        }
        if (-not $approvedStateVisible) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Approval process did not reach the recovery delay."
        }

        [System.IO.File]::WriteAllText(
            $statePath,
            $editC,
            [System.Text.UTF8Encoding]::new($false)
        )

        $process.WaitForExit()
        $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $exitCode = $process.ExitCode
        $after = [System.IO.File]::ReadAllText($statePath)
        $recoveryFiles = Get-ChildItem `
            -LiteralPath $dir `
            -Filter "*.codev-recovery-*" `
            -File `
            -Force `
            -ErrorAction SilentlyContinue

        Assert-Equal $exitCode 2 "Exit code"
        Assert-Contains $output "State changed during approval" "Output"
        Assert-Contains $after "Current gate: gate-recovery-c" "Latest gate preservation"
        Assert-Contains $after "Decision gate: gate-recovery-c" "Latest binding preservation"
        Assert-Contains $after "Recovery edit C." "Latest content preservation"
        Assert-Equal @($recoveryFiles).Count 0 "Resolved recovery file count"
    }
}

$tests += @{
    Name = "approve preserves Unix file permissions"
    Run = {
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            return
        }

        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-mode" `
            -Decision "pending" `
            -DecisionGate "gate-mode"
        $statePath = Join-Path $dir ".codev.md"
        & chmod 600 $statePath
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to set Unix fixture permissions."
        }

        $result = Run-CodeV `
            -ProjectRoot $dir `
            -Command "approve" `
            -GateId "gate-mode"
        $kernel = (& uname -s).Trim()
        if ($kernel -eq "Darwin") {
            $mode = (& stat -f "%Lp" $statePath).Trim()
        } else {
            $mode = (& stat -c "%a" $statePath).Trim()
        }

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Equal $mode "600" "Unix state file mode"
    }
}

$tests += @{
    Name = "approve preserves a concurrent Unix permission change"
    Run = {
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            return
        }

        $dir = New-Fixture
        Write-State `
            -ProjectRoot $dir `
            -CurrentGate "gate-mode-race" `
            -Decision "pending" `
            -DecisionGate "gate-mode-race"
        $statePath = Join-Path $dir ".codev.md"
        & chmod 600 $statePath
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to set initial Unix fixture permissions."
        }

        $powerShellExecutable = Get-PowerShellExecutable
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $codevScript,
            "approve",
            "-ProjectRoot",
            $dir,
            "-GateId",
            "gate-mode-race"
        )
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $powerShellExecutable
        $processInfo.Arguments = $arguments -join " "
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.Environment["CODEV_TEST_APPROVAL_DELAY_MS"] = "2000"
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $null = $process.Start()

        $tempPattern = "." + [System.IO.Path]::GetFileName($statePath) + ".codev-*.tmp"
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        $tempFile = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $tempFile = Get-ChildItem `
                -LiteralPath $dir `
                -Filter $tempPattern `
                -File `
                -Force `
                -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $tempFile) {
                break
            }
            if ($process.HasExited) {
                break
            }
            Start-Sleep -Milliseconds 20
        }
        if ($null -eq $tempFile) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Approval process did not pause before Unix metadata publication."
        }

        & chmod 640 $statePath
        if ($LASTEXITCODE -ne 0) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Unable to apply concurrent Unix fixture permissions."
        }

        $process.WaitForExit()
        $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $exitCode = $process.ExitCode
        $kernel = (& uname -s).Trim()
        if ($kernel -eq "Darwin") {
            $mode = (& stat -f "%Lp" $statePath).Trim()
        } else {
            $mode = (& stat -c "%a" $statePath).Trim()
        }

        Assert-Equal $exitCode 0 "Exit code"
        Assert-Contains $output "Human approval recorded for gate gate-mode-race." "Output"
        Assert-Equal $mode "640" "Concurrent Unix state file mode"
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
    Name = "approve preserves exact mixed newline bytes outside metadata values"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $beforeText = (
            "# CO-DEV`r`n" +
            "`n" +
            "Gate: strict`r`n" +
            "Ceremony: audit`n" +
            "Execution engine: custom:runner`r`n" +
            "Current gate: gate-mixed`n" +
            "Decision: rejected`r`n" +
            "Decision gate :   gate-mixed   `n" +
            "Unrelated preamble: keep exactly`r`n" +
            "`n" +
            "## Intent`r`n" +
            "Keep intent text.`n" +
            "## Shape`r`n" +
            "Keep shape text.`n" +
            "## Trace`r`n" +
            "Keep trace text."
        )
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
        [byte[]]$before = Get-EncodedBytes -Text $beforeText -Encoding $utf8NoBom
        [System.IO.File]::WriteAllBytes($statePath, $before)
        $expectedText = $beforeText.Replace("Decision: rejected", "Decision: approved")
        [byte[]]$expected = Get-EncodedBytes -Text $expectedText -Encoding $utf8NoBom

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-mixed"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval recorded for gate gate-mixed." "Output"
        Assert-ByteSequenceEqual $after $expected "Mixed newline and non-field bytes must remain exact."
    }
}

$tests += @{
    Name = "approve preserves UTF-8 BOM and exact encoded content"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $text = @(
            "# CO-DEV",
            "",
            "Gate: strict",
            "Ceremony: audit",
            "Execution engine: custom:runner",
            "Current gate: gate-utf8-bom",
            "Decision: pending",
            "Decision gate: gate-utf8-bom",
            "",
            "## Intent",
            "Keep BOM content."
        ) -join "`r`n"
        $utf8Bom = [System.Text.UTF8Encoding]::new($true, $true)
        [byte[]]$before = Get-EncodedBytes -Text $text -Encoding $utf8Bom -IncludePreamble
        [System.IO.File]::WriteAllBytes($statePath, $before)
        [byte[]]$expected = Get-EncodedBytes `
            -Text $text.Replace("Decision: pending", "Decision: approved") `
            -Encoding $utf8Bom `
            -IncludePreamble

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-utf8-bom"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-ByteSequenceEqual $after $expected "UTF-8 BOM and encoded content must be preserved."
    }
}

$tests += @{
    Name = "approve preserves UTF-16LE BOM and exact encoded content"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $unicodeText = "Keep snowman $([char]0x2603)."
        $text = @(
            "# CO-DEV",
            "",
            "Gate: strict",
            "Ceremony: audit",
            "Execution engine: custom:runner",
            "Current gate: gate-utf16",
            "Decision: rejected",
            "Decision gate: gate-utf16",
            "",
            "## Intent",
            $unicodeText
        ) -join "`n"
        $utf16Le = [System.Text.UnicodeEncoding]::new($false, $true, $true)
        [byte[]]$before = Get-EncodedBytes -Text $text -Encoding $utf16Le -IncludePreamble
        [System.IO.File]::WriteAllBytes($statePath, $before)
        [byte[]]$expected = Get-EncodedBytes `
            -Text $text.Replace("Decision: rejected", "Decision: approved") `
            -Encoding $utf16Le `
            -IncludePreamble

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-utf16"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-ByteSequenceEqual $after $expected "UTF-16LE BOM and encoded content must be preserved."
    }
}

$tests += @{
    Name = "approve preserves UTF-16BE BOM decoded content and non-field text"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $nonFieldText = "Keep UTF-16BE snowman $([char]0x2603) and trace text."
        $text = @(
            "# CO-DEV",
            "",
            "Gate: strict",
            "Ceremony: audit",
            "Execution engine: custom:runner",
            "Current gate: gate-utf16be",
            "Decision: pending",
            "Decision gate: gate-utf16be",
            "Unrelated preamble: preserve UTF-16BE",
            "",
            "## Intent",
            $nonFieldText,
            "## Trace",
            "Trace remains unchanged."
        ) -join "`r`n"
        $encoding = [System.Text.UnicodeEncoding]::new($true, $true, $true)
        [byte[]]$before = Get-EncodedBytes -Text $text -Encoding $encoding -IncludePreamble
        [System.IO.File]::WriteAllBytes($statePath, $before)
        $expectedText = $text.Replace("Decision: pending", "Decision: approved")
        [byte[]]$expected = Get-EncodedBytes `
            -Text $expectedText `
            -Encoding $encoding `
            -IncludePreamble

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-utf16be"
        [byte[]]$after = [System.IO.File]::ReadAllBytes($statePath)
        [byte[]]$preamble = $encoding.GetPreamble()
        [byte[]]$actualPreamble = $after[0..($preamble.Length - 1)]
        $decoded = $encoding.GetString(
            $after,
            $preamble.Length,
            $after.Length - $preamble.Length
        )

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Equal `
            $result.Output `
            ("Human approval recorded for gate gate-utf16be." + [Environment]::NewLine) `
            "Exact output"
        Assert-ByteSequenceEqual $actualPreamble $preamble "UTF-16BE BOM"
        Assert-ByteSequenceEqual $after $expected "UTF-16BE exact encoded content"
        Assert-Equal $decoded $expectedText "UTF-16BE decoded content"
        Assert-Contains $decoded $nonFieldText "UTF-16BE non-field text"
        Assert-Contains $decoded "Unrelated preamble: preserve UTF-16BE" "UTF-16BE preamble text"
        Assert-Contains $decoded "Trace remains unchanged." "UTF-16BE trace text"
    }
}

$tests += @{
    Name = "approve preserves UTF-32LE BOM decoded content and non-field text"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $nonFieldText = "Keep UTF-32LE snowman $([char]0x2603) and shape text."
        $text = @(
            "# CO-DEV",
            "",
            "Gate: strict",
            "Ceremony: audit",
            "Execution engine: custom:runner",
            "Current gate: gate-utf32le",
            "Decision: rejected",
            "Decision gate: gate-utf32le",
            "Unrelated preamble: preserve UTF-32LE",
            "",
            "## Intent",
            $nonFieldText,
            "## Shape",
            "Shape remains unchanged."
        ) -join "`n"
        $encoding = [System.Text.UTF32Encoding]::new($false, $true, $true)
        [byte[]]$before = Get-EncodedBytes -Text $text -Encoding $encoding -IncludePreamble
        [System.IO.File]::WriteAllBytes($statePath, $before)
        $expectedText = $text.Replace("Decision: rejected", "Decision: approved")
        [byte[]]$expected = Get-EncodedBytes `
            -Text $expectedText `
            -Encoding $encoding `
            -IncludePreamble

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-utf32le"
        [byte[]]$after = [System.IO.File]::ReadAllBytes($statePath)
        [byte[]]$preamble = $encoding.GetPreamble()
        [byte[]]$actualPreamble = $after[0..($preamble.Length - 1)]
        $decoded = $encoding.GetString(
            $after,
            $preamble.Length,
            $after.Length - $preamble.Length
        )

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-ByteSequenceEqual $actualPreamble $preamble "UTF-32LE BOM"
        Assert-ByteSequenceEqual $after $expected "UTF-32LE exact encoded content"
        Assert-Equal $decoded $expectedText "UTF-32LE decoded content"
        Assert-Contains $decoded $nonFieldText "UTF-32LE non-field text"
        Assert-Contains $decoded "Unrelated preamble: preserve UTF-32LE" "UTF-32LE preamble text"
        Assert-Contains $decoded "Shape remains unchanged." "UTF-32LE shape text"
    }
}

$tests += @{
    Name = "approve preserves UTF-32BE BOM decoded content and non-field text"
    Run = {
        $dir = New-Fixture
        $statePath = Join-Path $dir ".codev.md"
        $nonFieldText = "Keep UTF-32BE snowman $([char]0x2603) and intent text."
        $text = @(
            "# CO-DEV",
            "",
            "Gate: strict",
            "Ceremony: audit",
            "Execution engine: custom:runner",
            "Current gate: gate-utf32be",
            "Decision: pending",
            "Decision gate: gate-utf32be",
            "Unrelated preamble: preserve UTF-32BE",
            "",
            "## Intent",
            $nonFieldText,
            "## Trace",
            "Trace remains unchanged."
        ) -join "`r`n"
        $encoding = [System.Text.UTF32Encoding]::new($true, $true, $true)
        [byte[]]$before = Get-EncodedBytes -Text $text -Encoding $encoding -IncludePreamble
        [System.IO.File]::WriteAllBytes($statePath, $before)
        $expectedText = $text.Replace("Decision: pending", "Decision: approved")
        [byte[]]$expected = Get-EncodedBytes `
            -Text $expectedText `
            -Encoding $encoding `
            -IncludePreamble

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-utf32be"
        [byte[]]$after = [System.IO.File]::ReadAllBytes($statePath)
        [byte[]]$preamble = $encoding.GetPreamble()
        [byte[]]$actualPreamble = $after[0..($preamble.Length - 1)]
        $decoded = $encoding.GetString(
            $after,
            $preamble.Length,
            $after.Length - $preamble.Length
        )

        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-ByteSequenceEqual $actualPreamble $preamble "UTF-32BE BOM"
        Assert-ByteSequenceEqual $after $expected "UTF-32BE exact encoded content"
        Assert-Equal $decoded $expectedText "UTF-32BE decoded content"
        Assert-Contains $decoded $nonFieldText "UTF-32BE non-field text"
        Assert-Contains $decoded "Unrelated preamble: preserve UTF-32BE" "UTF-32BE preamble text"
        Assert-Contains $decoded "Trace remains unchanged." "UTF-32BE trace text"
    }
}

$tests += @{
    Name = "approve rejects undecodable unmarked bytes without modification"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-invalid-bytes" -Decision "pending" -DecisionGate "gate-invalid-bytes"
        $statePath = Join-Path $dir ".codev.md"
        [byte[]]$validBytes = [System.IO.File]::ReadAllBytes($statePath)
        [byte[]]$before = New-Object byte[] ($validBytes.Length + 1)
        [System.Array]::Copy($validBytes, $before, $validBytes.Length)
        $before[$before.Length - 1] = 0xFF
        [System.IO.File]::WriteAllBytes($statePath, $before)

        $result = Run-CodeV -ProjectRoot $dir -Command "approve" -GateId "gate-invalid-bytes"
        $after = [System.IO.File]::ReadAllBytes($statePath)

        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-ByteSequenceEqual $after $before "Undecodable unmarked bytes must not be rewritten."
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
    Name = "legacy check matches canonical check for valid approval"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -CurrentGate "gate-approved" -Decision "approved" -DecisionGate "gate-approved"
        $canonical = Run-CodeV -ProjectRoot $dir
        $legacy = Run-LegacyGate -ProjectRoot $dir
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 0 `
            -KeyOutput @("Human approval present for gate gate-approved.") `
            -Message "Valid approval parity"
    }
}

$tests += @{
    Name = "legacy check matches canonical check for pending gate"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "normal" -CurrentGate "gate-pending" -Decision "pending" -DecisionGate "gate-pending"
        $canonical = Run-CodeV -ProjectRoot $dir
        $legacy = Run-LegacyGate -ProjectRoot $dir
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 1 `
            -KeyOutput @("Human approval missing for normal gate gate-pending. Decision: pending.") `
            -Message "Pending gate parity"
    }
}

$tests += @{
    Name = "legacy check matches canonical rejection of stale decision gate"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -CurrentGate "gate-new" -Decision "approved" -DecisionGate "gate-old"
        $canonical = Run-CodeV -ProjectRoot $dir
        $legacy = Run-LegacyGate -ProjectRoot $dir
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 2 `
            -KeyOutput @("Decision gate 'gate-old' does not match Current gate 'gate-new'.") `
            -Message "Stale decision gate parity"
    }
}

$tests += @{
    Name = "legacy check matches canonical rejection of invalid ceremony"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Ceremony "nonsense" -CurrentGate "gate-invalid-ceremony" -Decision "approved" -DecisionGate "gate-invalid-ceremony"
        $canonical = Run-CodeV -ProjectRoot $dir
        $legacy = Run-LegacyGate -ProjectRoot $dir
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 2 `
            -KeyOutput @("Invalid Ceremony 'nonsense'.") `
            -Message "Invalid ceremony parity"
    }
}

$tests += @{
    Name = "legacy status matches canonical rejection of malformed state"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -OmitGate
        $canonical = Run-CodeV -ProjectRoot $dir -Command "status"
        $legacy = Run-LegacyGate -ProjectRoot $dir -Status
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 2 `
            -KeyOutput @("Missing 'Gate' in .codev.md.") `
            -Message "Malformed status parity"
    }
}

$tests += @{
    Name = "legacy status preserves project root paths with spaces"
    Run = {
        $fixtureRoot = New-Fixture
        $dir = Join-Path $fixtureRoot "project root with spaces"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-State -ProjectRoot $dir -CurrentGate "gate-project-spaces" -Decision "pending" -DecisionGate "gate-project-spaces"
        $canonical = Run-CodeV -ProjectRoot $dir -Command "status"
        $legacy = Run-LegacyGate -ProjectRoot $dir -Status
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 0 `
            -KeyOutput @(
                "CO-DEV status",
                "Current gate: gate-project-spaces",
                "Decision gate: gate-project-spaces"
            ) `
            -Message "Project root spaces parity"
    }
}

$tests += @{
    Name = "legacy check preserves explicit state paths with spaces"
    Run = {
        $fixtureRoot = New-Fixture
        $dir = Join-Path $fixtureRoot "state path project"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-State -ProjectRoot $dir -CurrentGate "gate-state-spaces" -Decision "approved" -DecisionGate "gate-state-spaces"
        $stateDirectory = Join-Path $dir "state folder with spaces"
        New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
        $statePath = Join-Path $stateDirectory "governance state.md"
        Move-Item -LiteralPath (Join-Path $dir ".codev.md") -Destination $statePath

        $canonical = Run-CodeV -ProjectRoot $dir -StatePath $statePath
        $legacy = Run-LegacyGate -ProjectRoot $dir -StatePath $statePath
        Assert-CommandParity `
            -Canonical $canonical `
            -Legacy $legacy `
            -ExpectedExitCode 0 `
            -KeyOutput @("Human approval present for gate gate-state-spaces.") `
            -Message "Explicit state path spaces parity"
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

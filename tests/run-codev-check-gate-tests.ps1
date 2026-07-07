$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root "scripts\codev-check-gate.ps1"

if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing gate script: $script"
}

function New-Fixture {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("codev-gate-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Run-Gate {
    param([string]$ProjectRoot)

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ProjectRoot $ProjectRoot 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
    }
}

function Write-State {
    param(
        [string]$ProjectRoot,
        [string]$Gate,
        [string]$Ceremony,
        [string]$CurrentGate,
        [string]$Decision
    )

    Set-Content -LiteralPath (Join-Path $ProjectRoot ".codev.md") -Value @"
# CO-DEV

Gate: $Gate
Ceremony: $Ceremony
Current gate: $CurrentGate
Decision: $Decision

## Intent
Fixture.
"@
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

$tests = @()

$tests += @{
    Name = "strict gate without approval fails"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -Ceremony "light" -CurrentGate "gate-1" -Decision "pending"
        $result = Run-Gate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 1 "Exit code"
        Assert-Contains $result.Output "Human approval missing" "Output"
    }
}

$tests += @{
    Name = "strict gate with approval passes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -Ceremony "light" -CurrentGate "gate-1" -Decision "approved"
        $result = Run-Gate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval present" "Output"
    }
}

$tests += @{
    Name = "strict gate with compact y approval passes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "strict" -Ceremony "light" -CurrentGate "gate-1" -Decision "y"
        $result = Run-Gate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Human approval present" "Output"
    }
}

$tests += @{
    Name = "free mode passes with low assurance warning"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "free" -Ceremony "light" -CurrentGate "gate-1" -Decision "pending"
        $result = Run-Gate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "Low-assurance mode" "Output"
    }
}

$tests += @{
    Name = "missing state fails"
    Run = {
        $dir = New-Fixture
        $result = Run-Gate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 2 "Exit code"
        Assert-Contains $result.Output "Missing CO-DEV state" "Output"
    }
}

$tests += @{
    Name = "no current gate passes"
    Run = {
        $dir = New-Fixture
        Write-State -ProjectRoot $dir -Gate "ultra" -Ceremony "light" -CurrentGate "none" -Decision "pending"
        $result = Run-Gate -ProjectRoot $dir
        Assert-Equal $result.ExitCode 0 "Exit code"
        Assert-Contains $result.Output "No current gate" "Output"
    }
}

$passed = 0
foreach ($test in $tests) {
    & $test.Run
    Write-Output "PASS $($test.Name)"
    $passed++
}

Write-Output "All $passed CO-DEV gate tests passed."

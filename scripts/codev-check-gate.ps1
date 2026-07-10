param(
    [string]$ProjectRoot = ".",
    [string]$StatePath,
    [switch]$Status
)

$ErrorActionPreference = "Stop"

function Get-PowerShellExecutable {
    if ($PSVersionTable.PSEdition -eq "Core") {
        return (Get-Process -Id $PID).Path
    }
    return (Join-Path $PSHOME "powershell.exe")
}

$codevScript = Join-Path $PSScriptRoot "codev.ps1"
$command = if ($Status) { "status" } else { "check" }
$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $codevScript,
    $command,
    "-ProjectRoot",
    $ProjectRoot
)
if ($PSBoundParameters.ContainsKey("StatePath")) {
    $arguments += @("-StatePath", $StatePath)
}

$powerShellExecutable = Get-PowerShellExecutable
& $powerShellExecutable @arguments
exit $LASTEXITCODE

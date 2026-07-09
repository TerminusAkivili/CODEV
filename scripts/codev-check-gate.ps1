param(
    [string]$ProjectRoot = ".",
    [string]$StatePath,
    [switch]$Status
)

$ErrorActionPreference = "Stop"

function Read-Field {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Text, "(?im)^\s*$escaped\s*:\s*(.+?)\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return $null
}

if (-not $StatePath) {
    $StatePath = Join-Path $ProjectRoot ".codev.md"
}

if (-not (Test-Path -LiteralPath $StatePath)) {
    Write-Output "Missing CO-DEV state: $StatePath"
    exit 2
}

$state = Get-Content -Raw -LiteralPath $StatePath
$gateLevel = Read-Field -Text $state -Name "Gate"
$ceremony = Read-Field -Text $state -Name "Ceremony"
$executionEngine = Read-Field -Text $state -Name "Execution engine"
$currentGate = Read-Field -Text $state -Name "Current gate"
$decision = Read-Field -Text $state -Name "Decision"

if ($Status) {
    Write-Output "CO-DEV status"
    Write-Output "Gate: $gateLevel"
    Write-Output "Ceremony: $ceremony"
    Write-Output "Execution engine: $executionEngine"
    Write-Output "Current gate: $currentGate"
    Write-Output "Decision: $decision"
    exit 0
}

if (-not $gateLevel) {
    Write-Output "Missing 'Gate' in .codev.md."
    exit 2
}

$gateLevel = $gateLevel.ToLowerInvariant()
$validLevels = @("ultra", "strict", "normal", "loose", "free")
if ($validLevels -notcontains $gateLevel) {
    Write-Output "Invalid gate '$gateLevel'. Expected one of: $($validLevels -join ', ')."
    exit 2
}

if ($gateLevel -eq "free") {
    Write-Output "Gate free: midstream human gate disabled. Low-assurance mode."
    exit 0
}

if (-not $currentGate) {
    Write-Output "Missing 'Current gate' in .codev.md."
    exit 2
}

$currentGateNormalized = $currentGate.ToLowerInvariant()
if ($currentGateNormalized -eq "none") {
    if ($ceremony) {
        Write-Output "No current gate. Ceremony: $ceremony."
    } else {
        Write-Output "No current gate."
    }
    exit 0
}

if (-not $decision) {
    Write-Output "Human approval missing for $gateLevel gate $currentGate."
    exit 1
}

$approvalWords = @("approved", "approve", "yes", "yep", "y")
if ($decision -and ($approvalWords -contains $decision.ToLowerInvariant())) {
    Write-Output "Human approval present for gate $currentGate."
    exit 0
}

Write-Output "Human approval missing for $gateLevel gate $currentGate. Decision: $decision."
exit 1

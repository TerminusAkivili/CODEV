param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "status", "approve")]
    [string]$Command = "check",

    [string]$ProjectRoot = ".",
    [string]$StatePath,
    [string]$GateId
)

$ErrorActionPreference = "Stop"

function Get-CanonicalFieldName {
    param([Parameter(Mandatory = $true)][string]$Name)

    switch ($Name.ToLowerInvariant()) {
        "gate" { return "Gate" }
        "ceremony" { return "Ceremony" }
        "execution engine" { return "Execution engine" }
        "current gate" { return "Current gate" }
        "decision" { return "Decision" }
        "decision gate" { return "Decision gate" }
        default { return $null }
    }
}

function Read-CodeVDocument {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path)
    $newlineMatch = [regex]::Match($text, "\r\n|\n|\r")
    if ($newlineMatch.Success) {
        $newline = $newlineMatch.Value
    } else {
        $newline = [Environment]::NewLine
    }

    $hasTrailingNewline = [regex]::IsMatch($text, "(\r\n|\n|\r)$")
    $lines = [regex]::Split($text, "\r\n|\n|\r")
    $fieldNames = @(
        "Gate",
        "Ceremony",
        "Execution engine",
        "Current gate",
        "Decision",
        "Decision gate"
    )
    $occurrences = @{}
    foreach ($fieldName in $fieldNames) {
        $occurrences[$fieldName] = @()
    }

    $metadataEndIndex = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -cmatch "^##\s") {
            $metadataEndIndex = $index
            break
        }

        $match = [regex]::Match(
            $line,
            "^\s*(Decision gate|Execution engine|Current gate|Ceremony|Decision|Gate)\s*:\s*(.*?)\s*$",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if (-not $match.Success) {
            continue
        }

        $canonicalName = Get-CanonicalFieldName -Name $match.Groups[1].Value
        $occurrences[$canonicalName] += [pscustomobject]@{
            LineIndex = $index
            Value = $match.Groups[2].Value.Trim()
        }
    }

    foreach ($fieldName in $fieldNames) {
        if ($occurrences[$fieldName].Count -eq 0) {
            throw "Missing '$fieldName' in .codev.md."
        }
        if ($occurrences[$fieldName].Count -gt 1) {
            throw "Duplicate '$fieldName' in .codev.md."
        }
    }

    $fieldLines = @{}
    foreach ($fieldName in $fieldNames) {
        $fieldLines[$fieldName] = $occurrences[$fieldName][0].LineIndex
    }

    return [pscustomobject]@{
        Path = $Path
        Text = $text
        Lines = $lines
        NewLine = $newline
        HasTrailingNewLine = $hasTrailingNewline
        MetadataEndIndex = $metadataEndIndex
        FieldLines = $fieldLines
        State = [pscustomobject]@{
            Gate = $occurrences["Gate"][0].Value
            Ceremony = $occurrences["Ceremony"][0].Value
            ExecutionEngine = $occurrences["Execution engine"][0].Value
            CurrentGate = $occurrences["Current gate"][0].Value
            Decision = $occurrences["Decision"][0].Value
            DecisionGate = $occurrences["Decision gate"][0].Value
        }
    }
}

function Assert-CodeVState {
    param([Parameter(Mandatory = $true)]$Document)

    $state = $Document.State
    $gate = $state.Gate.Trim()
    $ceremony = $state.Ceremony.Trim()
    $executionEngine = $state.ExecutionEngine.Trim()
    $currentGate = $state.CurrentGate.Trim()
    $decision = $state.Decision.Trim()
    $decisionGate = $state.DecisionGate.Trim()

    $normalizedGate = $gate.ToLowerInvariant()
    $validGates = @("ultra", "strict", "normal", "loose", "free")
    if ($validGates -notcontains $normalizedGate) {
        throw "Invalid Gate '$gate'. Expected one of: $($validGates -join ', ')."
    }

    $normalizedCeremony = $ceremony.ToLowerInvariant()
    $validCeremonies = @("light", "standard", "audit")
    if ($validCeremonies -notcontains $normalizedCeremony) {
        throw "Invalid Ceremony '$ceremony'. Expected one of: $($validCeremonies -join ', ')."
    }

    $normalizedExecutionEngine = $executionEngine.ToLowerInvariant()
    $validExecutionEngines = @("default", "superpower", "codex", "cursor")
    $isCustomExecutionEngine = $normalizedExecutionEngine -match "^custom:.+$"
    if (($validExecutionEngines -notcontains $normalizedExecutionEngine) -and -not $isCustomExecutionEngine) {
        throw "Invalid Execution engine '$executionEngine'. Expected default, superpower, codex, cursor, or custom:<non-empty>."
    }

    if ([string]::IsNullOrWhiteSpace($currentGate)) {
        throw "Invalid Current gate '$currentGate'. Expected 'none' or a non-empty identifier."
    }

    $normalizedDecision = $decision.ToLowerInvariant()
    $validDecisions = @(
        "pending",
        "approved",
        "approve",
        "yes",
        "yep",
        "y",
        "redirected",
        "rejected"
    )
    if ($validDecisions -notcontains $normalizedDecision) {
        throw "Invalid Decision '$decision'."
    }

    if (@("approved", "approve", "yes", "yep", "y") -contains $normalizedDecision) {
        $normalizedDecision = "approved"
    }

    if ([string]::IsNullOrWhiteSpace($decisionGate)) {
        throw "Invalid Decision gate '$decisionGate'. Expected 'none' or a non-empty identifier."
    }

    if ($currentGate -ieq "none") {
        if ($normalizedDecision -cne "pending") {
            throw "Decision must be 'pending' when Current gate is 'none'."
        }
        if ($decisionGate -ine "none") {
            throw "Decision gate must be 'none' when Current gate is 'none'."
        }
    } elseif ($decisionGate -cne $currentGate) {
        throw "Decision gate '$decisionGate' does not match Current gate '$currentGate'."
    }

    return [pscustomobject]@{
        Gate = $gate
        GateNormalized = $normalizedGate
        Ceremony = $ceremony
        CeremonyNormalized = $normalizedCeremony
        ExecutionEngine = $executionEngine
        ExecutionEngineNormalized = $normalizedExecutionEngine
        CurrentGate = $currentGate
        Decision = $decision
        DecisionNormalized = $normalizedDecision
        DecisionGate = $decisionGate
    }
}

function Invoke-CodeVCheck {
    param([Parameter(Mandatory = $true)]$State)

    if ($State.CurrentGate -ieq "none") {
        return [pscustomobject]@{
            ExitCode = 0
            Output = "No current gate. Ceremony: $($State.Ceremony)."
        }
    }

    if ($State.GateNormalized -eq "free") {
        return [pscustomobject]@{
            ExitCode = 0
            Output = "Gate free: midstream human gate disabled. Low-assurance mode."
        }
    }

    if ($State.DecisionNormalized -ceq "approved") {
        return [pscustomobject]@{
            ExitCode = 0
            Output = "Human approval present for gate $($State.CurrentGate)."
        }
    }

    return [pscustomobject]@{
        ExitCode = 1
        Output = "Human approval missing for $($State.GateNormalized) gate $($State.CurrentGate). Decision: $($State.Decision)."
    }
}

function Write-CodeVStatus {
    param([Parameter(Mandatory = $true)]$State)

    Write-Output "CO-DEV status"
    Write-Output "Gate: $($State.Gate)"
    Write-Output "Ceremony: $($State.Ceremony)"
    Write-Output "Execution engine: $($State.ExecutionEngine)"
    Write-Output "Current gate: $($State.CurrentGate)"
    Write-Output "Decision: $($State.Decision)"
    Write-Output "Decision gate: $($State.DecisionGate)"
}

try {
    if (-not $StatePath) {
        $StatePath = Join-Path $ProjectRoot ".codev.md"
    }

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        Write-Output "Missing CO-DEV state: $StatePath"
        exit 2
    }

    $document = Read-CodeVDocument -Path $StatePath
    $state = Assert-CodeVState -Document $document

    switch ($Command) {
        "check" {
            $checkResult = Invoke-CodeVCheck -State $state
            Write-Output $checkResult.Output
            exit $checkResult.ExitCode
        }
        "status" {
            Write-CodeVStatus -State $state
            exit 0
        }
        "approve" {
            Write-Output "The approve command is not implemented yet."
            exit 2
        }
    }
} catch {
    Write-Output $_.Exception.Message
    exit 2
}

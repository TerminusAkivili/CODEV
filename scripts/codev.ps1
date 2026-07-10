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

function ConvertFrom-CodeVText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Path
    )

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

    $lineIndex = 0
    $lineStart = 0
    while ($lineStart -lt $Text.Length) {
        $lineEnd = $lineStart
        while (
            $lineEnd -lt $Text.Length -and
            $Text[$lineEnd] -ne "`r" -and
            $Text[$lineEnd] -ne "`n"
        ) {
            $lineEnd++
        }

        $line = $Text.Substring($lineStart, $lineEnd - $lineStart)
        if ($line -cmatch "^##\s") {
            break
        }

        $match = [regex]::Match(
            $line,
            "^\s*(Decision gate|Execution engine|Current gate|Ceremony|Decision|Gate)\s*:\s*(.*?)\s*$",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
            $canonicalName = Get-CanonicalFieldName -Name $match.Groups[1].Value
            $occurrences[$canonicalName] += [pscustomobject]@{
                LineIndex = $lineIndex
                Value = $match.Groups[2].Value.Trim()
                ValueStart = $lineStart + $match.Groups[2].Index
                ValueLength = $match.Groups[2].Length
            }
        }

        if ($lineEnd -ge $Text.Length) {
            break
        }

        if (
            $Text[$lineEnd] -eq "`r" -and
            ($lineEnd + 1) -lt $Text.Length -and
            $Text[$lineEnd + 1] -eq "`n"
        ) {
            $lineStart = $lineEnd + 2
        } else {
            $lineStart = $lineEnd + 1
        }
        $lineIndex++
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

    $fieldLocations = @{}
    foreach ($fieldName in $fieldNames) {
        $fieldLocations[$fieldName] = [pscustomobject]@{
            Start = $occurrences[$fieldName][0].ValueStart
            Length = $occurrences[$fieldName][0].ValueLength
        }
    }

    return [pscustomobject]@{
        Path = $Path
        Text = $Text
        FieldLines = $fieldLines
        FieldLocations = $fieldLocations
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

function Read-CodeVDocument {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path)
    return ConvertFrom-CodeVText -Text $text -Path $Path
}

function Test-CodeVBytePrefix {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][byte[]]$Prefix
    )

    if ($Bytes.Length -lt $Prefix.Length) {
        return $false
    }

    for ($index = 0; $index -lt $Prefix.Length; $index++) {
        if ($Bytes[$index] -ne $Prefix[$index]) {
            return $false
        }
    }

    return $true
}

function ConvertFrom-CodeVBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $encoding = $null
    $preambleLength = 0
    $encodingName = $null

    if (Test-CodeVBytePrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFF, 0xFE, 0x00, 0x00))) {
        $encoding = [System.Text.UTF32Encoding]::new($false, $true, $true)
        $preambleLength = 4
        $encodingName = "UTF-32LE"
    } elseif (Test-CodeVBytePrefix -Bytes $Bytes -Prefix ([byte[]]@(0x00, 0x00, 0xFE, 0xFF))) {
        $encoding = [System.Text.UTF32Encoding]::new($true, $true, $true)
        $preambleLength = 4
        $encodingName = "UTF-32BE"
    } elseif (Test-CodeVBytePrefix -Bytes $Bytes -Prefix ([byte[]]@(0xEF, 0xBB, 0xBF))) {
        $encoding = [System.Text.UTF8Encoding]::new($true, $true)
        $preambleLength = 3
        $encodingName = "UTF-8 with BOM"
    } elseif (Test-CodeVBytePrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFF, 0xFE))) {
        $encoding = [System.Text.UnicodeEncoding]::new($false, $true, $true)
        $preambleLength = 2
        $encodingName = "UTF-16LE"
    } elseif (Test-CodeVBytePrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFE, 0xFF))) {
        $encoding = [System.Text.UnicodeEncoding]::new($true, $true, $true)
        $preambleLength = 2
        $encodingName = "UTF-16BE"
    } else {
        $encoding = [System.Text.UTF8Encoding]::new($false, $true)
        $encodingName = "UTF-8 without BOM"
    }

    try {
        $text = $encoding.GetString($Bytes, $preambleLength, $Bytes.Length - $preambleLength)
    } catch {
        throw "Unable to decode .codev.md as $encodingName."
    }

    [byte[]]$preamble = New-Object byte[] $preambleLength
    if ($preambleLength -gt 0) {
        [System.Array]::Copy($Bytes, 0, $preamble, 0, $preambleLength)
    }

    return [pscustomobject]@{
        Text = $text
        Encoding = $encoding
        EncodingName = $encodingName
        Preamble = $preamble
    }
}

function ConvertTo-CodeVBytes {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)]$EncodingInfo
    )

    [byte[]]$body = $EncodingInfo.Encoding.GetBytes($Text)
    [byte[]]$bytes = New-Object byte[] ($EncodingInfo.Preamble.Length + $body.Length)
    if ($EncodingInfo.Preamble.Length -gt 0) {
        [System.Array]::Copy(
            $EncodingInfo.Preamble,
            0,
            $bytes,
            0,
            $EncodingInfo.Preamble.Length
        )
    }
    if ($body.Length -gt 0) {
        [System.Array]::Copy(
            $body,
            0,
            $bytes,
            $EncodingInfo.Preamble.Length,
            $body.Length
        )
    }

    return $bytes
}

function Read-CodeVStreamBytes {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    if ($Stream.Length -gt [int]::MaxValue) {
        throw ".codev.md is too large to process."
    }

    [byte[]]$bytes = New-Object byte[] ([int]$Stream.Length)
    $Stream.Position = 0
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -eq 0) {
            throw "Unexpected end of .codev.md while reading."
        }
        $offset += $read
    }

    return $bytes
}

function Write-CodeVStreamBytes {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $Stream.Position = 0
    $Stream.SetLength(0)
    if ($Bytes.Length -gt 0) {
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }
    $Stream.Flush($true)
}

function Assert-CodeVBytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Actual,
        [Parameter(Mandatory = $true)][byte[]]$Expected
    )

    if ($Actual.Length -ne $Expected.Length) {
        throw "Approval write verification failed."
    }

    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) {
            throw "Approval write verification failed."
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

function Set-CodeVField {
    param(
        [Parameter(Mandatory = $true)]$Document,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if (-not $Document.FieldLocations.ContainsKey($Name)) {
        throw "Unknown CO-DEV field '$Name'."
    }

    $location = $Document.FieldLocations[$Name]
    return $Document.Text.Remove($location.Start, $location.Length).Insert($location.Start, $Value)
}

function Invoke-CodeVApprove {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$GateId
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        [byte[]]$originalBytes = Read-CodeVStreamBytes -Stream $stream
        $encodingInfo = ConvertFrom-CodeVBytes -Bytes $originalBytes
        $document = ConvertFrom-CodeVText -Text $encodingInfo.Text -Path $Path
        $state = Assert-CodeVState -Document $document

        if ($state.CurrentGate -ieq "none") {
            throw "Current gate is 'none'; there is no active gate to approve."
        }
        if ([string]::IsNullOrWhiteSpace($GateId)) {
            throw "GateId is required for approve."
        }
        if ($GateId -cne $state.CurrentGate) {
            throw "GateId '$GateId' does not exactly match Current gate '$($state.CurrentGate)'."
        }

        $updatedText = Set-CodeVField -Document $document -Name "Decision" -Value "approved"
        $updatedDocument = ConvertFrom-CodeVText -Text $updatedText -Path $Path
        $updatedText = Set-CodeVField `
            -Document $updatedDocument `
            -Name "Decision gate" `
            -Value $state.CurrentGate
        $updatedDocument = ConvertFrom-CodeVText -Text $updatedText -Path $Path
        $updatedState = Assert-CodeVState -Document $updatedDocument
        if ($updatedState.Decision -cne "approved") {
            throw "Approval update did not prepare Decision: approved."
        }
        if ($updatedState.DecisionGate -cne $state.CurrentGate) {
            throw "Approval update did not prepare the exact current gate."
        }

        [byte[]]$updatedBytes = ConvertTo-CodeVBytes `
            -Text $updatedText `
            -EncodingInfo $encodingInfo

        try {
            Write-CodeVStreamBytes -Stream $stream -Bytes $updatedBytes

            [byte[]]$persistedBytes = Read-CodeVStreamBytes -Stream $stream
            Assert-CodeVBytesEqual -Actual $persistedBytes -Expected $updatedBytes
            $persistedEncodingInfo = ConvertFrom-CodeVBytes -Bytes $persistedBytes
            $persistedDocument = ConvertFrom-CodeVText `
                -Text $persistedEncodingInfo.Text `
                -Path $Path
            $persistedState = Assert-CodeVState -Document $persistedDocument
            if ($persistedState.Decision -cne "approved") {
                throw "Approval write did not persist Decision: approved."
            }
            if ($persistedState.DecisionGate -cne $state.CurrentGate) {
                throw "Approval write did not persist the exact current gate."
            }
        } catch {
            $writeException = $_.Exception
            try {
                Write-CodeVStreamBytes -Stream $stream -Bytes $originalBytes
            } catch {
            }
            throw $writeException
        }

        return $state.CurrentGate
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
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

    if ($Command -ceq "approve") {
        $approvedGate = Invoke-CodeVApprove -Path $StatePath -GateId $GateId
        Write-Output "Human approval recorded for gate $approvedGate."
        exit 0
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
    }
} catch {
    Write-Output $_.Exception.Message
    exit 2
}

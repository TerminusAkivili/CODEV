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
    $fenceCharacter = $null
    $fenceLength = 0
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
        $nextLineStart = $Text.Length
        $nextLine = $null
        if ($lineEnd -lt $Text.Length) {
            if (
                $Text[$lineEnd] -eq "`r" -and
                ($lineEnd + 1) -lt $Text.Length -and
                $Text[$lineEnd + 1] -eq "`n"
            ) {
                $nextLineStart = $lineEnd + 2
            } else {
                $nextLineStart = $lineEnd + 1
            }

            if ($nextLineStart -lt $Text.Length) {
                $nextLineEnd = $nextLineStart
                while (
                    $nextLineEnd -lt $Text.Length -and
                    $Text[$nextLineEnd] -ne "`r" -and
                    $Text[$nextLineEnd] -ne "`n"
                ) {
                    $nextLineEnd++
                }
                $nextLine = $Text.Substring(
                    $nextLineStart,
                    $nextLineEnd - $nextLineStart
                )
            }
        }

        $parseMetadataLine = $true
        if ($null -ne $fenceCharacter) {
            $closingFencePattern = (
                "^ {0,3}" +
                [regex]::Escape($fenceCharacter) +
                "{$fenceLength,}[ \t]*$"
            )
            if ([regex]::IsMatch($line, $closingFencePattern)) {
                $fenceCharacter = $null
                $fenceLength = 0
            }
            $parseMetadataLine = $false
        } else {
            $openingFenceMatch = [regex]::Match(
                $line,
                '^( {0,3})(`{3,}|~{3,})(.*)$'
            )
            if ($openingFenceMatch.Success) {
                $fence = $openingFenceMatch.Groups[2].Value
                $fenceCharacter = $fence.Substring(0, 1)
                $fenceLength = $fence.Length
                $parseMetadataLine = $false
            } elseif ($line -cmatch "^ {0,3}##(?:[ \t]+|$)") {
                break
            }
        }

        if (
            $parseMetadataLine -and
            $line -cmatch "^ {0,3}\S" -and
            $null -ne $nextLine -and
            $nextLine -cmatch "^ {0,3}-+[ \t]*$"
        ) {
            break
        }

        if ($parseMetadataLine) {
            $match = [regex]::Match(
                $line,
                "^ {0,3}(Decision gate|Execution engine|Current gate|Ceremony|Decision|Gate)\s*:\s*(.*?)\s*$",
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
        }

        if ($lineEnd -ge $Text.Length) {
            break
        }

        $lineStart = $nextLineStart
        $lineIndex++
    }

    foreach ($fieldName in $fieldNames) {
        if ($occurrences[$fieldName].Count -eq 0) {
            if ($fieldName -ceq "Decision gate") {
                throw "Missing 'Decision gate' in .codev.md. Set it to 'none' or the active Current gate."
            }
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

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    $encodingInfo = ConvertFrom-CodeVBytes -Bytes $bytes
    return ConvertFrom-CodeVText -Text $encodingInfo.Text -Path $Path
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

function Test-CodeVBytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Actual,
        [Parameter(Mandatory = $true)][byte[]]$Expected
    )

    if ($Actual.Length -ne $Expected.Length) {
        return $false
    }

    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) {
            return $false
        }
    }

    return $true
}

function Assert-CodeVBytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Actual,
        [Parameter(Mandatory = $true)][byte[]]$Expected,
        [string]$Message = "Approval write verification failed."
    )

    if (-not (Test-CodeVBytesEqual -Actual $Actual -Expected $Expected)) {
        throw $Message
    }
}

function Get-CodeVLockPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $normalizedPath = $normalizedPath.ToUpperInvariant()
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        [byte[]]$pathBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
        [byte[]]$hashBytes = $sha256.ComputeHash($pathBytes)
    } finally {
        $sha256.Dispose()
    }

    $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    return Join-Path ([System.IO.Path]::GetTempPath()) "codev-approve-$hash.lock"
}

function Open-CodeVLockStream {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lockPath = Get-CodeVLockPath -Path $Path
    return [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
}

function Copy-CodeVFileForAtomicWrite {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        [System.IO.File]::Copy($SourcePath, $DestinationPath, $false)
        return
    }

    $kernel = (& uname -s).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the Unix platform for atomic approval."
    }

    if ($kernel -eq "Linux") {
        $copyOutput = & cp --preserve=all -- $SourcePath $DestinationPath 2>&1
    } elseif ($kernel -eq "Darwin") {
        $copyOutput = & cp -p $SourcePath $DestinationPath 2>&1
    } else {
        throw "Unsupported Unix platform '$kernel' for metadata-preserving approval."
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to preserve .codev.md metadata: $($copyOutput | Out-String)"
    }
}

function Write-CodeVPreparedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        if ($Bytes.Length -gt 0) {
            $stream.Write($Bytes, 0, $Bytes.Length)
        }
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-CodeVMetadataSignature {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return ""
    }

    $kernel = (& uname -s).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the Unix platform for metadata comparison."
    }

    if ($kernel -eq "Linux") {
        $tempRoot = Join-Path (
            [System.IO.Path]::GetTempPath()
        ) ("codev-metadata-" + [guid]::NewGuid().ToString("N"))
        $snapshotPath = Join-Path $tempRoot "snapshot"
        $archivePath = Join-Path $tempRoot "snapshot.tar"
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        try {
            $copyOutput = & cp --preserve=all -- $Path $snapshotPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to snapshot .codev.md metadata: $($copyOutput | Out-String)"
            }
            $tarOutput = & tar `
                --format=posix `
                --acls `
                --xattrs `
                --numeric-owner `
                --pax-option=delete=atime,delete=ctime `
                -cf $archivePath `
                -C $tempRoot `
                snapshot 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to archive .codev.md metadata: $($tarOutput | Out-String)"
            }

            [byte[]]$archiveBytes = [System.IO.File]::ReadAllBytes($archivePath)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                [byte[]]$hashBytes = $sha256.ComputeHash($archiveBytes)
            } finally {
                $sha256.Dispose()
            }
            return [System.BitConverter]::ToString($hashBytes).Replace("-", "")
        } finally {
            $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
            $resolvedSystemTemp = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::GetTempPath()
            )
            if (
                $resolvedTempRoot.StartsWith(
                    $resolvedSystemTemp,
                    [System.StringComparison]::Ordinal
                ) -and
                $resolvedTempRoot -ne $resolvedSystemTemp
            ) {
                Remove-Item `
                    -LiteralPath $resolvedTempRoot `
                    -Recurse `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }

    if ($kernel -eq "Darwin") {
        $statOutput = & stat -f "%p|%u|%g|%Sf" $Path 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read .codev.md stat metadata: $($statOutput | Out-String)"
        }
        $aclOutput = & ls -lde@ $Path 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read .codev.md ACL metadata: $($aclOutput | Out-String)"
        }
        $xattrOutput = & xattr -l $Path 2>&1
        if ($LASTEXITCODE -notin @(0, 1)) {
            throw "Unable to read .codev.md extended attributes: $($xattrOutput | Out-String)"
        }

        $normalizedAcl = ($aclOutput | Out-String).Replace($Path, "<path>").Trim()
        $normalizedXattr = ($xattrOutput | Out-String).Replace($Path, "<path>").Trim()
        return (
            ($statOutput | Out-String).Trim() +
            "`n" +
            $normalizedAcl +
            "`n" +
            $normalizedXattr
        )
    }

    throw "Unsupported Unix platform '$kernel' for metadata comparison."
}

function Get-CodeVFileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [pscustomobject]@{
        Bytes = [System.IO.File]::ReadAllBytes($Path)
        Metadata = Get-CodeVMetadataSignature -Path $Path
    }
}

function Test-CodeVFileSnapshotEqual {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected
    )

    return (
        (Test-CodeVBytesEqual -Actual $Actual.Bytes -Expected $Expected.Bytes) -and
        [string]::Equals(
            [string]$Actual.Metadata,
            [string]$Expected.Metadata,
            [System.StringComparison]::Ordinal
        )
    )
}

function Initialize-CodeVNativeFileSwap {
    if ($null -ne ("CodeV.NativeFileSwap" -as [type])) {
        return
    }

    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;

namespace CodeV
{
    public static class NativeFileSwap
    {
        [DllImport("libc", EntryPoint = "renameat2", SetLastError = true)]
        public static extern int RenameAt2(
            int oldDirectory,
            string oldPath,
            int newDirectory,
            string newPath,
            uint flags
        );

        [DllImport("libc", EntryPoint = "renamex_np", SetLastError = true)]
        public static extern int RenameX(
            string oldPath,
            string newPath,
            uint flags
        );
    }
}
"@
}

function Invoke-CodeVAtomicSwap {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$LivePath
    )

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $directory = [System.IO.Path]::GetDirectoryName(
            [System.IO.Path]::GetFullPath($LivePath)
        )
        $fileName = [System.IO.Path]::GetFileName($LivePath)
        $displacedPath = Join-Path $directory (
            ".$fileName.codev-displaced-" +
            [guid]::NewGuid().ToString("N") +
            ".tmp"
        )
        [System.IO.File]::Replace($CandidatePath, $LivePath, $displacedPath)
        return $displacedPath
    }

    Initialize-CodeVNativeFileSwap
    $kernel = (& uname -s).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the Unix platform for atomic swap."
    }

    if ($kernel -eq "Linux") {
        $result = [CodeV.NativeFileSwap]::RenameAt2(
            -100,
            $CandidatePath,
            -100,
            $LivePath,
            2
        )
    } elseif ($kernel -eq "Darwin") {
        $result = [CodeV.NativeFileSwap]::RenameX(
            $CandidatePath,
            $LivePath,
            2
        )
    } else {
        throw "Unsupported Unix platform '$kernel' for atomic swap."
    }

    if ($result -ne 0) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $errorMessage = [System.ComponentModel.Win32Exception]::new(
            $errorCode
        ).Message
        throw "Atomic file swap failed: $errorMessage (errno $errorCode)."
    }

    return $CandidatePath
}

function Restore-CodeVFileSafely {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)]$ExpectedLiveSnapshot,
        [int]$MaxAttempts = 8
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $candidate = $CandidatePath
    $expected = $ExpectedLiveSnapshot

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $candidateSnapshot = Get-CodeVFileSnapshot -Path $candidate
        $displacedPath = Invoke-CodeVAtomicSwap `
            -CandidatePath $candidate `
            -LivePath $fullPath
        $displacedSnapshot = Get-CodeVFileSnapshot -Path $displacedPath
        if (
            Test-CodeVFileSnapshotEqual `
                -Actual $displacedSnapshot `
                -Expected $expected
        ) {
            Remove-Item `
                -LiteralPath $displacedPath `
                -Force `
                -ErrorAction SilentlyContinue
            return
        }

        $candidate = $displacedPath
        $expected = $candidateSnapshot
    }

    throw (
        "Concurrent state changes did not settle during recovery. " +
        "Latest recovery retained at '$candidate'."
    )
}

function Sync-CodeVUnixMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$MetadataSourcePath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)]$ExpectedLiveSnapshot
    )

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    $fileName = [System.IO.Path]::GetFileName($fullPath)
    $operationId = [guid]::NewGuid().ToString("N")
    $tempPath = Join-Path $directory ".$fileName.codev-$operationId.metadata.tmp"
    $displacedPath = $null
    $candidateSnapshot = $null
    $swapCompleted = $false

    try {
        Copy-CodeVFileForAtomicWrite `
            -SourcePath $MetadataSourcePath `
            -DestinationPath $tempPath
        Write-CodeVPreparedFile -Path $tempPath -Bytes $Bytes
        $candidateSnapshot = Get-CodeVFileSnapshot -Path $tempPath
        $displacedPath = Invoke-CodeVAtomicSwap `
            -CandidatePath $tempPath `
            -LivePath $fullPath
        $swapCompleted = $true
    } catch {
        $syncException = $_.Exception
        try {
            Restore-CodeVFileSafely `
                -Path $fullPath `
                -CandidatePath $MetadataSourcePath `
                -ExpectedLiveSnapshot $expectedLiveSnapshot
        } catch {
            throw (
                "Unix metadata synchronization failed and recovery did not complete. " +
                "Sync error: $($syncException.Message) Recovery error: $($_.Exception.Message)"
            )
        }
        throw $syncException
    } finally {
        if (
            -not $swapCompleted -and
            (Test-Path -LiteralPath $tempPath -PathType Leaf)
        ) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    $displacedSnapshot = Get-CodeVFileSnapshot -Path $displacedPath
    if (
        -not (
            Test-CodeVFileSnapshotEqual `
                -Actual $displacedSnapshot `
                -Expected $expectedLiveSnapshot
        )
    ) {
        try {
            Restore-CodeVFileSafely `
                -Path $fullPath `
                -CandidatePath $displacedPath `
                -ExpectedLiveSnapshot $candidateSnapshot
        } finally {
            Remove-Item `
                -LiteralPath $MetadataSourcePath `
                -Force `
                -ErrorAction SilentlyContinue
        }
        throw "State changed during approval metadata synchronization."
    }

    [byte[]]$persistedBytes = [System.IO.File]::ReadAllBytes($fullPath)
    Assert-CodeVBytesEqual -Actual $persistedBytes -Expected $Bytes
    Remove-Item -LiteralPath $displacedPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $MetadataSourcePath -Force -ErrorAction SilentlyContinue
}

function Get-CodeVTestDelayMilliseconds {
    param([Parameter(Mandatory = $true)][string]$EnvironmentVariable)

    $delayText = [System.Environment]::GetEnvironmentVariable($EnvironmentVariable)
    if ([string]::IsNullOrWhiteSpace($delayText)) {
        return 0
    }

    $delayMilliseconds = 0
    if (
        -not [int]::TryParse($delayText, [ref]$delayMilliseconds) -or
        $delayMilliseconds -lt 0 -or
        $delayMilliseconds -gt 10000
    ) {
        throw "Invalid $EnvironmentVariable value."
    }
    return $delayMilliseconds
}

function Invoke-CodeVTestDelay {
    param([int]$Milliseconds)

    if ($Milliseconds -gt 0) {
        Start-Sleep -Milliseconds $Milliseconds
    }
}

function Publish-CodeVBytesAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][byte[]]$ExpectedBytes
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    $fileName = [System.IO.Path]::GetFileName($fullPath)
    $operationId = [guid]::NewGuid().ToString("N")
    $tempPath = Join-Path $directory ".$fileName.codev-$operationId.tmp"
    $backupPath = $null
    $publishedSnapshot = $null
    $swapCompleted = $false
    $publicationDelay = Get-CodeVTestDelayMilliseconds `
        -EnvironmentVariable "CODEV_TEST_APPROVAL_DELAY_MS"
    $recoveryDelay = Get-CodeVTestDelayMilliseconds `
        -EnvironmentVariable "CODEV_TEST_APPROVAL_RECOVERY_DELAY_MS"
    $metadataDelay = Get-CodeVTestDelayMilliseconds `
        -EnvironmentVariable "CODEV_TEST_APPROVAL_METADATA_DELAY_MS"

    try {
        Copy-CodeVFileForAtomicWrite `
            -SourcePath $fullPath `
            -DestinationPath $tempPath
        Write-CodeVPreparedFile -Path $tempPath -Bytes $Bytes
        $publishedSnapshot = Get-CodeVFileSnapshot -Path $tempPath

        Invoke-CodeVTestDelay -Milliseconds $publicationDelay

        $backupPath = Invoke-CodeVAtomicSwap `
            -CandidatePath $tempPath `
            -LivePath $fullPath
        $swapCompleted = $true
    } catch {
        throw $_.Exception
    } finally {
        if (
            -not $swapCompleted -and
            (Test-Path -LiteralPath $tempPath -PathType Leaf)
        ) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        [byte[]]$replacedBytes = [System.IO.File]::ReadAllBytes($backupPath)
        Assert-CodeVBytesEqual `
            -Actual $replacedBytes `
            -Expected $ExpectedBytes `
            -Message "State changed during approval; approval was not recorded."
        [byte[]]$persistedBytes = [System.IO.File]::ReadAllBytes($fullPath)
        Assert-CodeVBytesEqual -Actual $persistedBytes -Expected $Bytes
    } catch {
        $publishException = $_.Exception
        try {
            Invoke-CodeVTestDelay -Milliseconds $recoveryDelay
            Restore-CodeVFileSafely `
                -Path $fullPath `
                -CandidatePath $backupPath `
                -ExpectedLiveSnapshot $publishedSnapshot
        } catch {
            throw (
                "Approval publication failed and recovery did not complete. " +
                "Publish error: $($publishException.Message) " +
                "Recovery error: $($_.Exception.Message)"
            )
        }
        throw $publishException
    }

    Invoke-CodeVTestDelay -Milliseconds $metadataDelay
    Sync-CodeVUnixMetadata `
        -Path $fullPath `
        -MetadataSourcePath $backupPath `
        -Bytes $Bytes `
        -ExpectedLiveSnapshot $publishedSnapshot

    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-CodeVOrdinalMember {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string[]]$AllowedValues
    )

    foreach ($allowedValue in $AllowedValues) {
        if ([string]::Equals(
            $Value,
            $allowedValue,
            [System.StringComparison]::Ordinal
        )) {
            return $true
        }
    }

    return $false
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
    if (-not (
        Test-CodeVOrdinalMember `
            -Value $normalizedGate `
            -AllowedValues $validGates
    )) {
        throw "Invalid Gate '$gate'. Expected one of: $($validGates -join ', ')."
    }

    $normalizedCeremony = $ceremony.ToLowerInvariant()
    $validCeremonies = @("light", "standard", "audit")
    if (-not (
        Test-CodeVOrdinalMember `
            -Value $normalizedCeremony `
            -AllowedValues $validCeremonies
    )) {
        throw "Invalid Ceremony '$ceremony'. Expected one of: $($validCeremonies -join ', ')."
    }

    $normalizedExecutionEngine = $executionEngine.ToLowerInvariant()
    $validExecutionEngines = @("default", "superpower", "codex", "cursor")
    $isCustomExecutionEngine = $normalizedExecutionEngine -match "^custom:.+$"
    $isFixedExecutionEngine = Test-CodeVOrdinalMember `
        -Value $normalizedExecutionEngine `
        -AllowedValues $validExecutionEngines
    if (-not $isFixedExecutionEngine -and -not $isCustomExecutionEngine) {
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
    if (-not (
        Test-CodeVOrdinalMember `
            -Value $normalizedDecision `
            -AllowedValues $validDecisions
    )) {
        throw "Invalid Decision '$decision'."
    }

    if (Test-CodeVOrdinalMember `
        -Value $normalizedDecision `
        -AllowedValues @("approved", "approve", "yes", "yep", "y")
    ) {
        $normalizedDecision = "approved"
    }

    if ([string]::IsNullOrWhiteSpace($decisionGate)) {
        throw "Invalid Decision gate '$decisionGate'. Expected 'none' or a non-empty identifier."
    }

    $currentGateIsNone = [string]::Equals(
        $currentGate,
        "none",
        [System.StringComparison]::Ordinal
    )
    if (
        -not $currentGateIsNone -and
        [string]::Equals(
            $currentGate,
            "none",
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Current gate sentinel must be exactly 'none'."
    }

    $decisionGateIsNone = [string]::Equals(
        $decisionGate,
        "none",
        [System.StringComparison]::Ordinal
    )
    if (
        -not $decisionGateIsNone -and
        [string]::Equals(
            $decisionGate,
            "none",
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Decision gate sentinel must be exactly 'none'."
    }

    if ($currentGateIsNone) {
        if (-not [string]::Equals(
            $normalizedDecision,
            "pending",
            [System.StringComparison]::Ordinal
        )) {
            throw "Decision must be 'pending' when Current gate is 'none'."
        }
        if (-not $decisionGateIsNone) {
            throw "Decision gate must be 'none' when Current gate is 'none'."
        }
    } elseif (-not [string]::Equals(
        $decisionGate,
        $currentGate,
        [System.StringComparison]::Ordinal
    )) {
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

    $lockStream = $null
    try {
        $lockStream = Open-CodeVLockStream -Path $Path
        [byte[]]$originalBytes = [System.IO.File]::ReadAllBytes($Path)
        $encodingInfo = ConvertFrom-CodeVBytes -Bytes $originalBytes
        $document = ConvertFrom-CodeVText -Text $encodingInfo.Text -Path $Path
        $state = Assert-CodeVState -Document $document

        if ([string]::Equals(
            $state.CurrentGate,
            "none",
            [System.StringComparison]::Ordinal
        )) {
            throw "Current gate is 'none'; there is no active gate to approve."
        }
        if ([string]::IsNullOrWhiteSpace($GateId)) {
            throw "GateId is required for approve."
        }
        if (-not [string]::Equals(
            $GateId,
            $state.CurrentGate,
            [System.StringComparison]::Ordinal
        )) {
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
        if (-not [string]::Equals(
            $updatedState.Decision,
            "approved",
            [System.StringComparison]::Ordinal
        )) {
            throw "Approval update did not prepare Decision: approved."
        }
        if (-not [string]::Equals(
            $updatedState.DecisionGate,
            $state.CurrentGate,
            [System.StringComparison]::Ordinal
        )) {
            throw "Approval update did not prepare the exact current gate."
        }

        [byte[]]$updatedBytes = ConvertTo-CodeVBytes `
            -Text $updatedText `
            -EncodingInfo $encodingInfo

        Publish-CodeVBytesAtomically `
            -Path $Path `
            -Bytes $updatedBytes `
            -ExpectedBytes $originalBytes

        [byte[]]$persistedBytes = [System.IO.File]::ReadAllBytes($Path)
        $persistedEncodingInfo = ConvertFrom-CodeVBytes -Bytes $persistedBytes
        $persistedDocument = ConvertFrom-CodeVText `
            -Text $persistedEncodingInfo.Text `
            -Path $Path
        $persistedState = Assert-CodeVState -Document $persistedDocument
        if (-not [string]::Equals(
            $persistedState.Decision,
            "approved",
            [System.StringComparison]::Ordinal
        )) {
            throw "Approval write did not persist Decision: approved."
        }
        if (-not [string]::Equals(
            $persistedState.DecisionGate,
            $state.CurrentGate,
            [System.StringComparison]::Ordinal
        )) {
            throw "Approval write did not persist the exact current gate."
        }

        return $state.CurrentGate
    } finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
        }
    }
}

function Invoke-CodeVCheck {
    param([Parameter(Mandatory = $true)]$State)

    if ([string]::Equals(
        $State.CurrentGate,
        "none",
        [System.StringComparison]::Ordinal
    )) {
        return [pscustomobject]@{
            ExitCode = 0
            Output = "No current gate. Ceremony: $($State.Ceremony)."
        }
    }

    if ([string]::Equals(
        $State.GateNormalized,
        "free",
        [System.StringComparison]::Ordinal
    )) {
        return [pscustomobject]@{
            ExitCode = 0
            Output = "Gate free: midstream human gate disabled. Low-assurance mode."
        }
    }

    if ([string]::Equals(
        $State.DecisionNormalized,
        "approved",
        [System.StringComparison]::Ordinal
    )) {
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

    $normalizedCommand = $Command.ToLowerInvariant()
    if ([string]::Equals(
        $normalizedCommand,
        "approve",
        [System.StringComparison]::Ordinal
    )) {
        $approvedGate = Invoke-CodeVApprove -Path $StatePath -GateId $GateId
        Write-Output "Human approval recorded for gate $approvedGate."
        exit 0
    }

    $document = Read-CodeVDocument -Path $StatePath
    $state = Assert-CodeVState -Document $document
    if ([string]::Equals(
        $normalizedCommand,
        "check",
        [System.StringComparison]::Ordinal
    )) {
        $checkResult = Invoke-CodeVCheck -State $state
        Write-Output $checkResult.Output
        exit $checkResult.ExitCode
    }
    if ([string]::Equals(
        $normalizedCommand,
        "status",
        [System.StringComparison]::Ordinal
    )) {
        Write-CodeVStatus -State $state
        exit 0
    }
    throw "Unsupported CO-DEV command '$Command'."
} catch {
    Write-Output $_.Exception.Message
    exit 2
}

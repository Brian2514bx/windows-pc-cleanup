<#
.SYNOPSIS
  Move user-approved files/folders to the Recycle Bin (never permanent delete).
  Dry run by default: prints what would happen. Add -Execute to actually move.

.PARAMETER ListFile
  Text file, one path per line. Lines starting with # are ignored.
  A path ending in \* means "the contents of this folder" (the folder itself stays),
  which is how temp/cache folders should be listed.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\recycle.ps1 -ListFile .\approved.txt
  powershell -NoProfile -ExecutionPolicy Bypass -File .\recycle.ps1 -ListFile .\approved.txt -Execute
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ListFile,
    [switch]$Execute,
    [string]$LogFile = ''
)

Add-Type -AssemblyName Microsoft.VisualBasic
$ErrorActionPreference = 'Stop'

# Paths that must never be recycled, even if listed. Compared case-insensitively as prefixes / exact matches.
$UP = $env:USERPROFILE
$protectedPrefixes = @(
    "$env:SystemRoot",                       # C:\Windows (includes System32, WinSxS)
    "$env:ProgramFiles",
    "${env:ProgramFiles(x86)}",
    "$env:ProgramData\Microsoft",
    "$env:SystemDrive\Recovery",
    "$env:SystemDrive\System Volume Information",
    "$env:SystemDrive\Boot"
) | Where-Object { $_ }
$protectedExact = @(
    "$env:SystemDrive\", $UP, "$UP\Desktop", "$UP\Documents", "$UP\Pictures", "$UP\Videos", "$UP\Music",
    "$UP\Downloads", "$UP\OneDrive", "$env:APPDATA", "$env:LOCALAPPDATA", "$UP\AppData",
    "$env:APPDATA\.minecraft", "$env:APPDATA\.minecraft\saves", "$env:ProgramData"
)
# Whole-drive roots are protected too
Get-PSDrive -PSProvider FileSystem | ForEach-Object { $protectedExact += $_.Root }
$protectedNames = @('pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'bootmgr', 'ntuser.dat')

function Norm([string]$p) { return ([IO.Path]::GetFullPath($p)).TrimEnd('\').ToLowerInvariant() }
$protectedExactN = $protectedExact | Where-Object { $_ } | ForEach-Object { Norm $_ }
$protectedPrefixN = $protectedPrefixes | ForEach-Object { Norm $_ }

function Test-Protected([string]$path) {
    $n = Norm $path
    if ($protectedExactN -contains $n) { return 'protected location' }
    foreach ($pp in $protectedPrefixN) { if ($n -eq $pp -or $n.StartsWith($pp + '\')) { return "inside protected area ($pp)" } }
    if ($protectedNames -contains ([IO.Path]::GetFileName($n))) { return 'system file' }
    if ($n -match '\\saves(\\|$)') { return 'looks like game saves' }
    return $null
}

$log = New-Object System.Collections.Generic.List[string]
function Log($s) { Write-Host $s; $log.Add($s) }

$items = Get-Content -LiteralPath $ListFile -Encoding UTF8 | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -and -not $_.StartsWith('#') }

# Expand "folder\*" into its children
$targets = New-Object System.Collections.Generic.List[string]
foreach ($i in $items) {
    if ($i.EndsWith('\*')) {
        $folder = $i.Substring(0, $i.Length - 2)
        $why = Test-Protected $folder
        if ($why -and -not ((Norm $folder) -eq (Norm $env:TEMP) -or (Norm $folder) -eq (Norm "$env:SystemRoot\Temp"))) {
            # contents of a protected folder are only allowed for the two temp folders
            Log "SKIP  (contents of $why) $i"; continue
        }
        Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | ForEach-Object { $targets.Add($_.FullName) }
    } else { $targets.Add($i) }
}

$mode = if ($Execute) { 'EXECUTE' } else { 'DRY RUN (nothing will be moved; add -Execute to move)' }
Log "Mode: $mode"
$totalBytes = 0L; $moved = 0; $skipped = 0

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t)) { Log "SKIP  (not found) $t"; $skipped++; continue }
    $isTempChild = ((Norm (Split-Path $t -Parent)) -eq (Norm $env:TEMP)) -or ((Norm (Split-Path $t -Parent)) -eq (Norm "$env:SystemRoot\Temp"))
    $why = Test-Protected $t
    if ($why -and -not $isTempChild) { Log "SKIP  ($why) $t"; $skipped++; continue }

    $item = Get-Item -LiteralPath $t -Force
    $size = 0L
    if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $t -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $size += $_.Length }
    } else { $size = $item.Length }

    if (-not $Execute) {
        Log ("WOULD {0,10:N1} MB  {1}" -f ($size / 1MB), $t); $totalBytes += $size; $moved++; continue
    }
    try {
        if ($item.PSIsContainer) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($t, 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($t, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        Log ("MOVED {0,10:N1} MB  {1}" -f ($size / 1MB), $t); $totalBytes += $size; $moved++
    } catch {
        Log "SKIP  (in use or no permission) $t"; $skipped++
    }
}

$verb = if ($Execute) { 'Moved to Recycle Bin' } else { 'Would move' }
Log ("{0}: {1} item(s), {2:N1} MB. Skipped: {3}." -f $verb, $moved, ($totalBytes / 1MB), $skipped)

if ($LogFile) { [IO.File]::WriteAllLines($LogFile, $log, (New-Object Text.UTF8Encoding($false))) }

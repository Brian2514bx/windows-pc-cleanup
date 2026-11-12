<#
.SYNOPSIS
  Read-only scan of a Windows PC for the windows-pc-cleanup skill.
  Writes report.json (full data) and report.txt (short summary) to -OutDir.
  This script never deletes, moves, or changes anything.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan.ps1 -OutDir .\pc-scan
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan.ps1 -OutDir .\pc-scan -ScanPaths "D:\" -TopN 80
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\scan.ps1 -PickFolder
  When report_template.html sits next to this script, report.html is generated and opened at the end.
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $env:USERPROFILE "Desktop\pc-scan"),
    [string[]]$ScanPaths = @(),
    [int]$TopN = 50,
    [int]$MinLargeMB = 300,
    [switch]$Quick,
    [switch]$PickFolder,   # show a folder picker so the user can add folders/drives to the large-file search
    [switch]$NoOpen        # do not open report.html when finished
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$started = Get-Date

function Say($msg) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg) }

function Get-FolderSize([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $sum = 0L; $count = 0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += $_.Length; $count++ }
    return [pscustomobject]@{ bytes = $sum; files = $count }
}

function MB($bytes) { if ($null -eq $bytes) { return 0 } ; return [math]::Round($bytes / 1MB, 1) }

# ---------------------------------------------------------------- optional folder picker
$IsZh = (Get-UICulture).Name -like 'zh*'
if ($PickFolder) {
    Add-Type -AssemblyName System.Windows.Forms
    $nl = [Environment]::NewLine
    if ($IsZh) {
        $txtTitle = '電腦整理 - 選擇掃描範圍'
        $txtAsk   = '要另外選擇資料夾或磁碟（例如 D:\）一起找大型檔案嗎？' + $nl + '使用者資料夾（桌面、文件、下載…）一定會掃描。'
        $txtDesc  = '選擇要一起掃描的資料夾或磁碟'
        $txtMore  = '已加入：{0}' + $nl + '還要再加入其他資料夾嗎？'
    } else {
        $txtTitle = 'PC Cleanup - choose what to scan'
        $txtAsk   = 'Add another folder or drive (e.g. D:\) to the large-file search?' + $nl + 'Your user folders (Desktop, Documents, Downloads...) are always scanned.'
        $txtDesc  = 'Choose a folder or drive to include in the scan'
        $txtMore  = 'Added: {0}' + $nl + 'Add another folder?'
    }
    $ask = $txtAsk
    while ([System.Windows.Forms.MessageBox]::Show($ask, $txtTitle, 'YesNo', 'Question') -eq 'Yes') {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $txtDesc
        $dlg.ShowNewFolderButton = $false
        $dlg.RootFolder = [Environment+SpecialFolder]::MyComputer   # start at This PC so C:\ D:\ are listed first
        if ($dlg.ShowDialog() -eq 'OK' -and $dlg.SelectedPath) { $ScanPaths += $dlg.SelectedPath; Write-Host ("  + " + $dlg.SelectedPath) }
        $ask = $txtMore -f ($ScanPaths -join ', ')
    }
}

$null = New-Item -ItemType Directory -Force -Path $OutDir
$UP = $env:USERPROFILE
$LA = $env:LOCALAPPDATA
$RA = $env:APPDATA

$report = [ordered]@{
    generatedAt = $started.ToString('s')
    computer    = $env:COMPUTERNAME
    user        = $env:USERNAME
    os          = (Get-CimInstance Win32_OperatingSystem).Caption
    uiCulture   = (Get-UICulture).Name
    scanPaths   = @($ScanPaths)
    isAdmin     = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- drives
Say "Drives..."
$report.drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    [pscustomobject]@{
        drive   = $_.DeviceID
        label   = $_.VolumeName
        totalGB = [math]::Round($_.Size / 1GB, 1)
        freeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
        freePct = if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } else { 0 }
    }
})

# ---------------------------------------------------------------- cleanable locations
# risk: safe = rebuilds automatically / pure temp; check = user should look first
Say "Temp and cache folders..."
$candidates = @(
    @{ name = 'User temp files (%TEMP%)';            path = $env:TEMP;                                         risk = 'safe';  note = 'Temporary files; locked ones are skipped' }
    @{ name = 'Windows temp files';                  path = "$env:SystemRoot\Temp";                            risk = 'safe';  note = 'Needs admin to clean fully' }
    @{ name = 'Crash dumps';                         path = "$LA\CrashDumps";                                  risk = 'safe';  note = 'Old crash dumps' }
    @{ name = 'Windows error reports';               path = "$env:ProgramData\Microsoft\Windows\WER";          risk = 'safe';  note = 'Error report archives' }
    @{ name = 'DirectX shader cache';                path = "$LA\D3DSCache";                                   risk = 'safe';  note = 'Rebuilds; first game launch may be slower' }
    @{ name = 'NVIDIA DX shader cache';              path = "$LA\NVIDIA\DXCache";                              risk = 'safe';  note = 'Rebuilds; first game launch may be slower' }
    @{ name = 'NVIDIA GL shader cache';              path = "$LA\NVIDIA\GLCache";                              risk = 'safe';  note = 'Rebuilds; first game launch may be slower' }
    @{ name = 'Chrome cache';                        path = "$LA\Google\Chrome\User Data\Default\Cache";       risk = 'safe';  note = 'Close Chrome first; does not remove logins or history' }
    @{ name = 'Chrome code cache';                   path = "$LA\Google\Chrome\User Data\Default\Code Cache";  risk = 'safe';  note = 'Close Chrome first' }
    @{ name = 'Edge cache';                          path = "$LA\Microsoft\Edge\User Data\Default\Cache";      risk = 'safe';  note = 'Close Edge first; does not remove logins or history' }
    @{ name = 'Edge code cache';                     path = "$LA\Microsoft\Edge\User Data\Default\Code Cache"; risk = 'safe';  note = 'Close Edge first' }
    @{ name = 'Discord cache';                       path = "$RA\discord\Cache";                               risk = 'safe';  note = 'Close Discord first' }
    @{ name = 'Discord code cache';                  path = "$RA\discord\Code Cache";                          risk = 'safe';  note = 'Close Discord first' }
    @{ name = 'Steam web cache';                     path = "$LA\Steam\htmlcache";                             risk = 'safe';  note = 'Close Steam first' }
    @{ name = 'Windows Update download cache';       path = "$env:SystemRoot\SoftwareDistribution\Download";   risk = 'check'; note = 'Prefer Settings > Storage > Temporary files to clean this' }
    @{ name = 'Downloads folder';                    path = (Join-Path $UP 'Downloads');                       risk = 'check'; note = 'User files - review item by item' }
    @{ name = 'Minecraft logs (.minecraft)';         path = "$RA\.minecraft\logs";                             risk = 'safe';  note = 'Old game logs' }
    @{ name = 'Minecraft crash reports';             path = "$RA\.minecraft\crash-reports";                    risk = 'safe';  note = 'Old crash reports' }
    @{ name = 'CurseForge Minecraft instances';      path = "$UP\curseforge\minecraft\Instances";              risk = 'check'; note = 'Contains worlds/saves - only remove whole modpacks the user no longer plays' }
    @{ name = 'Lunar Client';                        path = "$UP\.lunarclient";                                risk = 'check'; note = 'Only if the user no longer uses Lunar Client' }
)
$cleanable = @(foreach ($c in $candidates) {
    $s = Get-FolderSize $c.path
    if ($s -and $s.bytes -gt 0) {
        [pscustomobject]@{ name = $c.name; path = $c.path; sizeMB = (MB $s.bytes); files = $s.files; risk = $c.risk; note = $c.note }
    }
})
# Recycle Bin size (per drive)
foreach ($d in $report.drives) {
    $rb = Join-Path ($d.drive + '\') '$Recycle.Bin'
    $s = Get-FolderSize $rb
    if ($s -and $s.bytes -gt 0) {
        $cleanable += [pscustomobject]@{ name = "Recycle Bin ($($d.drive))"; path = $rb; sizeMB = (MB $s.bytes); files = $s.files; risk = 'check'; note = 'Emptying is permanent - user should do it themselves after checking' }
    }
}
$report.cleanable = @($cleanable | Sort-Object sizeMB -Descending)

# ---------------------------------------------------------------- large files & folders
$excludeRx = '^(?i)[A-Z]:\\(Windows|\$Recycle\.Bin|System Volume Information|ProgramData\\Microsoft\\Windows\\WER)(\\|$)'
if (-not $Quick) {
    $roots = @($UP) + $ScanPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    Say ("Large files under: " + ($roots -join ', ') + " (this can take a few minutes)")
    $minBytes = [int64]$MinLargeMB * 1MB
    $big = New-Object System.Collections.Generic.List[object]
    foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge $minBytes -and $_.FullName -notmatch $excludeRx -and $_.Name -notin @('pagefile.sys','hiberfil.sys','swapfile.sys') } |
            ForEach-Object {
                $big.Add([pscustomobject]@{
                    path = $_.FullName; sizeMB = (MB $_.Length)
                    lastWrite = $_.LastWriteTime.ToString('yyyy-MM-dd'); lastAccess = $_.LastAccessTime.ToString('yyyy-MM-dd')
                    ext = $_.Extension.ToLower()
                })
            }
    }
    $report.largeFiles = @($big | Sort-Object sizeMB -Descending | Select-Object -First $TopN)

    Say "Folder sizes (top level of each root)..."
    $folders = foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $excludeRx -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
            ForEach-Object {
                $s = Get-FolderSize $_.FullName
                if ($s) { [pscustomobject]@{ path = $_.FullName; sizeMB = (MB $s.bytes); files = $s.files } }
            }
    }
    $report.largeFolders = @($folders | Sort-Object sizeMB -Descending | Select-Object -First 30)
} else {
    $report.largeFiles = @(); $report.largeFolders = @()
}

# ---------------------------------------------------------------- installed programs
Say "Installed programs..."
$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$programs = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName } |
    ForEach-Object {
        $date = $null
        if ($_.InstallDate -match '^\d{8}$') { $date = '{0}-{1}-{2}' -f $_.InstallDate.Substring(0,4), $_.InstallDate.Substring(4,2), $_.InstallDate.Substring(6,2) }
        [pscustomobject]@{
            name = $_.DisplayName; publisher = $_.Publisher; version = $_.DisplayVersion
            installDate = $date
            sizeMB = if ($_.EstimatedSize) { [math]::Round($_.EstimatedSize / 1024, 1) } else { $null }
            location = $_.InstallLocation
        }
    } | Sort-Object name -Unique
$report.programs = @($programs)

# ---------------------------------------------------------------- startup items
Say "Startup items..."
function Get-ExePath([string]$cmd) {
    if (-not $cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c.StartsWith('"')) { return ($c.Substring(1) -split '"')[0] }
    if ($c -match '^(.+?\.(exe|bat|cmd|vbs|js|ps1|com|scr|jar))(\s|$)') { return $Matches[1] }
    return ($c -split '\s')[0]
}
function Describe-Exe([string]$exe) {
    $exists = $false; $sig = 'Unknown'; $signer = $null; $flags = @()
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        $exists = $true
        $a = Get-AuthenticodeSignature -LiteralPath $exe
        if ($a) { $sig = [string]$a.Status; if ($a.SignerCertificate) { $signer = $a.SignerCertificate.Subject } }
    } elseif ($exe) { $flags += 'file-missing' }
    if ($exe -match '(?i)\\(Temp|Downloads)\\') { $flags += 'runs-from-temp-or-downloads' }
    if ($exe -match '(?i)\\AppData\\(Roaming|Local)\\[^\\]+\.(exe|scr|bat|vbs|js)$') { $flags += 'exe-directly-in-appdata' }
    if ($exe -match '(?i)\.(vbs|js|bat|cmd|ps1|scr|jar)$') { $flags += 'script-or-unusual-type' }
    if ($exists -and $sig -ne 'Valid') { $flags += 'not-validly-signed' }
    return @{ exists = $exists; signature = $sig; signer = $signer; flags = $flags }
}

$startup = New-Object System.Collections.Generic.List[object]
$runKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($k in $runKeys) {
    $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if (-not $props) { continue }
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        $exe = Get-ExePath ([string]$p.Value)
        $d = Describe-Exe $exe
        $startup.Add([pscustomobject]@{ source = $k; name = $p.Name; command = [string]$p.Value; exe = $exe; exists = $d.exists; signature = $d.signature; signer = $d.signer; flags = $d.flags })
    }
}
$startupFolders = @("$RA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp")
foreach ($f in $startupFolders) {
    Get-ChildItem -LiteralPath $f -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
        $target = $_.FullName
        if ($_.Extension -eq '.lnk') { $target = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).TargetPath }
        $d = Describe-Exe $target
        $startup.Add([pscustomobject]@{ source = $f; name = $_.Name; command = $target; exe = $target; exists = $d.exists; signature = $d.signature; signer = $d.signer; flags = $d.flags })
    }
}
# Scheduled tasks outside \Microsoft\ that run a program
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' } | ForEach-Object {
    $t = $_
    foreach ($a in @($t.Actions)) {
        if (-not $a.Execute) { continue }
        $exe = Get-ExePath $a.Execute
        $d = Describe-Exe $exe
        $startup.Add([pscustomobject]@{ source = 'ScheduledTask'; name = ($t.TaskPath + $t.TaskName); command = ($a.Execute + ' ' + $a.Arguments).Trim(); exe = $exe; exists = $d.exists; signature = $d.signature; signer = $d.signer; flags = $d.flags })
    }
}
$report.startup = $startup.ToArray()   # @(List) throws 'Argument types do not match' on PS 5.1

# ---------------------------------------------------------------- security hints
Say "Security hints..."
$sec = [ordered]@{}

$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp) {
    $sec.defender = [pscustomobject]@{
        antivirusEnabled     = $mp.AntivirusEnabled
        realTimeProtection   = $mp.RealTimeProtectionEnabled
        signatureAgeDays     = $mp.AntivirusSignatureAge
        lastQuickScan        = if ($mp.QuickScanEndTime) { $mp.QuickScanEndTime.ToString('s') } else { $null }
        lastFullScan         = if ($mp.FullScanEndTime) { $mp.FullScanEndTime.ToString('s') } else { $null }
    }
    $sec.recentThreats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 20 | ForEach-Object {
        [pscustomobject]@{ detected = $_.InitialDetectionTime.ToString('s'); threatId = $_.ThreatID; resources = ($_.Resources -join '; '); actionSuccess = $_.ActionSuccess }
    })
} else {
    $sec.defender = 'unavailable (third-party antivirus, or no permission)'
}

$sec.flaggedStartup = @($startup | Where-Object { $_.flags.Count -gt 0 })

# Executables / scripts sitting in Temp or Downloads (changed in the last 90 days)
$execExt = @('.exe','.scr','.bat','.cmd','.vbs','.js','.ps1','.msi','.jar','.dll')
$cut = (Get-Date).AddDays(-90)
$sec.recentExecutablesInTempOrDownloads = @(
    foreach ($p in @($env:TEMP, (Join-Path $UP 'Downloads'))) {
        Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $execExt -contains $_.Extension.ToLower() -and $_.LastWriteTime -ge $cut } |
            Select-Object -First 200 | ForEach-Object {
                $s = Get-AuthenticodeSignature -LiteralPath $_.FullName
                [pscustomobject]@{ path = $_.FullName; sizeMB = (MB $_.Length); modified = $_.LastWriteTime.ToString('yyyy-MM-dd'); signature = [string]$s.Status }
            }
    }
)

# Known indicator files of the 2023 "fractureiser" Minecraft-mod malware (Windows stage).
# Note the space in "Microsoft Edge" under LOCALAPPDATA - the real Edge lives under LOCALAPPDATA\Microsoft\Edge.
$fractureiser = @()
foreach ($p in @("$LA\Microsoft Edge\libWebGL64.jar", "$LA\Microsoft Edge\lib.dll")) {
    if (Test-Path -LiteralPath $p) { $fractureiser += $p }
}
$fractureiserRun = @($startup | Where-Object { $_.command -match '(?i)Microsoft Edge\\(libWebGL64\.jar|lib\.dll)' })
$sec.fractureiserIndicators = [pscustomobject]@{ files = $fractureiser; startupEntries = @($fractureiserRun | ForEach-Object { $_.command }) }

# Minecraft mod jars: list with hashes so they can be checked on Modrinth/CurseForge or VirusTotal
if (-not $Quick) {
    $modRoots = @("$RA\.minecraft\mods", "$UP\curseforge\minecraft\Instances", "$RA\PrismLauncher\instances", "$RA\.minecraft\versions")
    $jars = foreach ($m in $modRoots) {
        if (Test-Path -LiteralPath $m) {
            Get-ChildItem -LiteralPath $m -Recurse -Force -File -Filter *.jar -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '(?i)\\mods\\' } |
                ForEach-Object {
                    [pscustomobject]@{ path = $_.FullName; sizeKB = [math]::Round($_.Length / 1KB); modified = $_.LastWriteTime.ToString('yyyy-MM-dd'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
                }
        }
    }
    $sec.minecraftModJars = @($jars)
    $sec.minecraftModJarCount = @($jars).Count
}
$report.security = $sec

# ---------------------------------------------------------------- write output
$report.elapsedSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds)
$json = $report | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $OutDir 'report.json'), $json, (New-Object Text.UTF8Encoding($false)))

$lines = @()
$lines += "PC scan  $($report.generatedAt)  ($($report.elapsedSeconds)s)  admin=$($report.isAdmin)"
$lines += ''
$lines += 'DRIVES'
$report.drives | ForEach-Object { $lines += ("  {0}  {1} GB free of {2} GB ({3}%)" -f $_.drive, $_.freeGB, $_.totalGB, $_.freePct) }
$lines += ''
$lines += 'CLEANABLE (MB, risk)'
$report.cleanable | ForEach-Object { $lines += ("  {0,10}  {1,-5}  {2}" -f $_.sizeMB, $_.risk, $_.name) }
$lines += ''
$lines += "LARGE FILES (top $TopN, >= $MinLargeMB MB)"
$report.largeFiles | Select-Object -First 15 | ForEach-Object { $lines += ("  {0,10}  {1}" -f $_.sizeMB, $_.path) }
$lines += ''
$lines += ("PROGRAMS: {0}   STARTUP ITEMS: {1}   FLAGGED STARTUP: {2}" -f $report.programs.Count, $report.startup.Count, $sec.flaggedStartup.Count)
$lines += ("EXECUTABLES IN TEMP/DOWNLOADS (90d): {0}" -f $sec.recentExecutablesInTempOrDownloads.Count)
$lines += ("FRACTUREISER INDICATORS: {0}" -f ($fractureiser.Count + $fractureiserRun.Count))
[IO.File]::WriteAllText((Join-Path $OutDir 'report.txt'), ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- visual report
$template = Join-Path $PSScriptRoot 'report_template.html'
if (Test-Path -LiteralPath $template) {
    $html = [IO.File]::ReadAllText($template, [Text.Encoding]::UTF8)
    $html = $html.Replace('/*__REPORT_JSON__*/null', $json.Replace('</', '<\/'))
    $htmlPath = Join-Path $OutDir 'report.html'
    [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    if (-not $NoOpen) { Start-Process $htmlPath }
    Say "Done. Visual report: $htmlPath (also report.json, report.txt). Nothing was changed."
} else {
    Say "Done. Report saved to $OutDir (report.json, report.txt). Nothing was changed."
}

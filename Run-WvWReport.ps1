# Run-WvWReport.ps1
#
# One-command pipeline: parse all zevtc logs in a folder -> combine into one
# session -> generate data.json for the web dashboard, written straight into
# your GitHub repo folder.
#
# USAGE:
#   .\Run-WvWReport.ps1 -LogFolder "C:\path\to\your\zevtc\folder"
#
# EDIT THE PATHS BELOW ONCE to match where you installed things.

param(
    [Parameter(Mandatory=$true)]
    [string]$LogFolder,

    [string]$GuildName = "Echoes of the Vanguard (ECHO)"
)

# ---------- ONE-TIME SETUP: EDIT THESE PATHS ----------
$EIExe        = "C:\Users\newpc\Desktop\echologs\GW2-Elite-Insights-Parser-master\GW2EI.bin\Release\CLI\GuildWars2EliteInsights-CLI.exe"
$TopStatsExe  = "C:\Users\newpc\Desktop\echologs\TopStats_v1.7.5\TopStats.exe"
$TopStatsIni  = "C:\Users\newpc\Desktop\echologs\TopStats_v1.7.5\top_stats_config.ini"
$PythonScript = "C:\Users\newpc\Desktop\echologs\build_report_data.py"
$RepoFolder   = "C:\Users\newpc\Desktop\echologs\inhouseecholog"
$ArchiveFolder = "C:\Users\newpc\Desktop\echologs\archived_fights_json"
$TokenFile    = Join-Path $RepoFolder "dps-report-token.txt"
# --------------------------------------------------------

$ErrorActionPreference = "Stop"

if (-not (Test-Path $TokenFile)) {
    Write-Error "Token file not found: $TokenFile`nCreate it with your dps.report token as the only line (see README)."
    exit 1
}
$DpsReportToken = (Get-Content $TokenFile -Raw).Trim()
if (-not $DpsReportToken -or $DpsReportToken -eq "PASTE_YOUR_DPS_REPORT_TOKEN_HERE") {
    Write-Error "$TokenFile still has a placeholder value. Paste your real dps.report token in that file."
    exit 1
}

if (-not (Test-Path $LogFolder)) {
    Write-Error "Log folder not found: $LogFolder"
    exit 1
}

$JsonOutput = Join-Path $LogFolder "json_output"
if (Test-Path $JsonOutput) {
    Write-Host "Clearing old json_output contents to avoid combining stale fights..." -ForegroundColor Yellow
    Get-ChildItem -Path $JsonOutput -File | Remove-Item -Force
}
New-Item -ItemType Directory -Force -Path $JsonOutput | Out-Null

# ---------- Step 1: Parse zevtc -> JSON with Elite Insights ----------
Write-Host "`n[1/3] Parsing zevtc logs with Elite Insights..." -ForegroundColor Cyan

$TempConf = Join-Path $env:TEMP "wvw_session_json_temp.conf"
@"
SaveAtOut=false
OutLocation=$JsonOutput
SaveOutTrace=false
Anonymous=false
AddPoVProf=true
AddDuration=true
SingleThreaded=false
ParseMultipleLogs=true
SkipFailedTries=true
ParsePhases=true
ParseCombatReplay=true
ComputeDamageModifiers=true
DetailledWvW=true
SaveOutHTML=false
SaveOutCSV=false
SaveOutJSON=true
IndentJSON=false
SaveOutXML=false
CompressRaw=false
RawTimelineArrays=true
UploadToDPSReports=true
DPSReportUserToken=$DpsReportToken
UploadToWingman=false
UploadToMistWarrior=false
MemoryLimit=0
"@ | Set-Content -Path $TempConf -Encoding ASCII

$logFiles = (Get-ChildItem "$LogFolder\*.zevtc").FullName
if (-not $logFiles) {
    Write-Error "No .zevtc files found in $LogFolder"
    exit 1
}

$eiOutput = & $EIExe -c $TempConf $logFiles 2>&1 | Tee-Object -Variable eiOutputLines
if ($LASTEXITCODE -ne 0) {
    Write-Error "Elite Insights CLI exited with code $LASTEXITCODE."
    exit 1
}

# ---------- Capture dps.report links per fight from the console "Processed - {...}" lines ----------
# TopStats.exe does not carry these links into its combined output, so we capture them
# ourselves here and match them back to fights later using their timestamp.
Write-Host "Extracting dps.report links from parser output..." -ForegroundColor Cyan
$linksMap = @{}
foreach ($line in $eiOutputLines) {
    if ($line -match '^Processed - (\{.*\})$') {
        try {
            $obj = $Matches[1] | ConvertFrom-Json
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($obj.fileName)
            if ($obj.dpsReportLink) {
                $linksMap[$baseName] = $obj.dpsReportLink
            }
        } catch {
            # Ignore lines that don't parse cleanly as JSON
        }
    }
}
$linksMapPath = Join-Path $LogFolder "dps_links.json"
$linksMap | ConvertTo-Json | Set-Content -Path $linksMapPath -Encoding UTF8
Write-Host "Captured $($linksMap.Count) dps.report links -> $linksMapPath" -ForegroundColor Green

Write-Host "Parsing complete. JSON files written to $JsonOutput" -ForegroundColor Green

# ---------- Step 2: Combine JSON into one session ----------
Write-Host "`n[2/3] Combining logs into one session summary..." -ForegroundColor Cyan

# Point the combiner's config at this session's JSON folder
(Get-Content $TopStatsIni) |
    ForEach-Object {
        if ($_ -match '^\s*input_directory\s*=') {
            "input_directory = $JsonOutput"
        } else {
            $_
        }
    } | Set-Content $TopStatsIni

$TopStatsDir = Split-Path $TopStatsExe -Parent
Push-Location $TopStatsDir
& $TopStatsExe
Pop-Location

# Find the freshest combined stats file (TopStats.exe writes this into the
# input JSON folder itself, not next to TopStats.exe)
$combinedJson = Get-ChildItem -Path $JsonOutput -Recurse -Filter "TW5_top_stats_*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $combinedJson) {
    Write-Error "Could not find a combined TW5_top_stats_*.json output. Check TopStats.exe ran correctly."
    exit 1
}

Write-Host "Combined session data: $($combinedJson.FullName)" -ForegroundColor Green

# ---------- Archive the combined session file (small, kept forever, outside the repo) ----------
New-Item -ItemType Directory -Force -Path $ArchiveFolder | Out-Null
$archivePath = Join-Path $ArchiveFolder $combinedJson.Name
Copy-Item -Path $combinedJson.FullName -Destination $archivePath -Force
Write-Host "Archived combined session to: $archivePath" -ForegroundColor Green

# ---------- Step 3: Generate data.json for the web dashboard ----------
Write-Host "`n[3/3] Generating data.json..." -ForegroundColor Cyan

$dateStamp = Get-Date -Format "yyyy-MM-dd"
$dataPath = Join-Path $RepoFolder "data.json"

python $PythonScript $combinedJson.FullName $dataPath "$GuildName" "$dateStamp" "$linksMapPath"

if (Test-Path $dataPath) {
    Write-Host "`nDone! data.json written to:" -ForegroundColor Green
    Write-Host $dataPath -ForegroundColor Yellow
    Write-Host "`nNext: cd `"$RepoFolder`", then git add . ; git commit -m `"update report`" ; git push" -ForegroundColor Green
} else {
    Write-Error "data.json generation failed."
}
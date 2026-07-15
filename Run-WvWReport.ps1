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
$EIExe        = "C:\Users\newpc\Downloads\GW2EI\GuildWars2EliteInsights.exe"
$TopStatsExe  = "C:\Users\newpc\Downloads\TopStats_v1.7.5\TopStats.exe"
$TopStatsIni  = "C:\Users\newpc\Downloads\TopStats_v1.7.5\top_stats_config.ini"
$PythonScript = "C:\Users\newpc\Downloads\build_report_data.py"
$RepoFolder   = "C:\Users\newpc\Desktop\echologs\inhouseecholog"
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

& $EIExe -c $TempConf $logFiles

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

# Find the freshest combined stats file
$combinedJson = Get-ChildItem -Path $TopStatsDir -Recurse -Filter "TW5_top_stats_*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $combinedJson) {
    Write-Error "Could not find a combined TW5_top_stats_*.json output. Check TopStats.exe ran correctly."
    exit 1
}

Write-Host "Combined session data: $($combinedJson.FullName)" -ForegroundColor Green

# ---------- Step 3: Generate data.json for the web dashboard ----------
Write-Host "`n[3/3] Generating data.json..." -ForegroundColor Cyan

$dateStamp = Get-Date -Format "yyyy-MM-dd"
$dataPath = Join-Path $RepoFolder "data.json"

python $PythonScript $combinedJson.FullName $dataPath "$GuildName" "$dateStamp"

if (Test-Path $dataPath) {
    Write-Host "`nDone! data.json written to:" -ForegroundColor Green
    Write-Host $dataPath -ForegroundColor Yellow
    Write-Host "`nNext: cd `"$RepoFolder`", then git add . ; git commit -m `"update report`" ; git push" -ForegroundColor Green
} else {
    Write-Error "data.json generation failed."
}

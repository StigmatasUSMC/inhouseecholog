# WvW Session Report Pipeline

Turns a folder of `.zevtc` combat logs into a live, sortable web dashboard
hosted on GitHub Pages, with per-fight report links.

## Files

| File | What it does | Where it lives |
|---|---|---|
| `Run-WvWReport.ps1` | The one command you run each session. Parses all zevtc logs, combines them into one session, and writes `data.json` straight into your repo folder. | Anywhere convenient, e.g. `Downloads` |
| `build_report_data.py` | Converts the combined session data into the compact `data.json` the website reads. Called automatically by the PowerShell script, you never run it by hand. | Anywhere convenient, e.g. `Downloads` |
| `index.html` | The actual dashboard: sidebar nav, charts, sortable tables, fight log with report links. Plain HTML/CSS/JS, no build step. Only needs updating if you want to redesign the page itself. | Inside your repo folder (`inhouseecholog`) |
| `data.json` | Your current session's data. Regenerated and overwritten every time you run the pipeline. | Inside your repo folder (`inhouseecholog`) |
| `dps-report-token.txt` | Your real dps.report token, one line, nothing else. **Never committed to git**, see `.gitignore`. | Inside your repo folder, but gitignored |
| `.gitignore` | Tells git to never track `dps-report-token.txt`, so your token can never end up in the public repo. | Inside your repo folder (`inhouseecholog`) |

## Tools this depends on (not included, download separately)

- **[Elite Insights](https://github.com/baaron4/GW2-Elite-Insights-Parser)** — parses `.zevtc` into JSON.
- **[GW2_EI_log_combiner / TopStats](https://github.com/Drevarr/GW2_EI_log_combiner)** — combines multiple fight JSONs into one session summary.
- **Python 3** with `pip install matplotlib python-docx` (matplotlib isn't strictly needed anymore since we moved to the web dashboard, but harmless to have).
- **Git**, already confirmed installed (Git Bash).

## One-time setup

1. Open `Run-WvWReport.ps1` and edit the paths near the top:
   - `$EIExe` → path to `GuildWars2EliteInsights.exe`
   - `$TopStatsExe` → path to `TopStats.exe`
   - `$TopStatsIni` → path to `top_stats_config.ini`
   - `$PythonScript` → path to `build_report_data.py`
   - `$RepoFolder` → path to your cloned `inhouseecholog` repo folder
2. Copy `.gitignore` and `dps-report-token.txt` into your repo folder. Open
   `dps-report-token.txt` and replace the placeholder with your real
   [dps.report](https://dps.report) token (get one at
   `https://dps.report/getUserToken`, treat it like a password). Because
   `.gitignore` lists this file, it will never be pushed to GitHub even
   though it lives in the repo folder.
3. Copy `index.html` and `data.json` into your repo folder too, then
   `git add . ; git commit -m "initial dashboard" ; git push`. Git will
   silently skip the token file thanks to `.gitignore`, confirm this by
   checking `git status`, it should not appear as a tracked/staged file.
4. On github.com, go to the repo's **Settings > Pages**, set Source to
   **Deploy from a branch**, branch **main**, folder **/ (root)**, Save.
5. Your dashboard is live at `https://stigmatasusmc.github.io/inhouseecholog/`.

## Every session after that

```powershell
.\Run-WvWReport.ps1 -LogFolder "C:\path\to\your\zevtc\folder"
cd C:\Users\newpc\Desktop\echologs\inhouseecholog
git add .
git commit -m "update report"
git push
```

That's it, `index.html` never needs to change again unless you want to redesign
the page. Only `data.json` gets regenerated and pushed each time.

## Known limitations, worth remembering

- **10v10 filter**: the Fight Log tab excludes fights under 10 squad / 10 enemy
  participants (matches your guild's AxiBridge setting). The raid summary
  totals and player leaderboards, however, still include *all* fights, since
  those numbers come pre-combined from `TopStats.exe` and can't be safely
  decomposed back down to per-fight numbers after the fact. If you want fully
  filtered leaderboards too, the fix has to happen upstream: exclude the
  failing zevtc files before running Elite Insights at all.
- **Per-fight report links**: only populate if `UploadToDPSReports=true` and a
  valid `DPSReportUserToken` are set when Elite Insights runs. Today's example
  `data.json` has empty links since that wasn't enabled yet when it was
  generated.
- **Editing the dashboard**: everything, colors, fonts, sections, charts,
  table columns, lives in `index.html`. See the `:root { }` CSS block for
  theme colors/fonts, the `<nav>`/`<section>` blocks for tabs, and the
  `render()` function in the `<script>` block for what data feeds what.

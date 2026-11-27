<#
.SYNOPSIS
  One-command end-to-end validation of the Kloud Kart solution on a fresh load.

.DESCRIPTION
  0. Pre-flight: checks the six CSVs (headers, field counts, IDs, row counts)
     with scripts/preflight_csv.ps1 before anything is loaded.
  1. Checks the server allows enough connections for the 400-buyer test.
  2. Creates a disposable database and runs sql/run_all.sql (load, audits,
     schema changes, functions, and the self-checking assertions).
  3. Runs the supplied data/race_test.py, unmodified, -RaceRuns times.
  4. Times the customer report and the low-stock rollup (median of 3).
  5. Drops the database and writes evidence/final_validation.md.

  Exit code 0 only if every step passes.

  Tested on Windows PowerShell 5.1. It only uses cross-platform cmdlets, docker
  and the venv's Python, so it is written to run under PowerShell 7 (pwsh) on
  macOS/Linux too, but that has not been tested.

.EXAMPLE
  .\scripts\validate_all.ps1          # Windows
  pwsh ./scripts/validate_all.ps1     # macOS/Linux with PowerShell 7
#>
param(
    [int]$RaceRuns = 3,
    [string]$Container = "kloudkart-db",
    [string]$HostPort = "5432",
    [double]$ReportBudgetMs = 10000,
    [double]$RollupBudgetMs = 2000
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
# Windows venvs keep Python in Scripts\, macOS/Linux venvs in bin/.
$Python = @(
    (Join-Path $Root ".venv/Scripts/python.exe"),
    (Join-Path $Root ".venv/bin/python")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Python) { throw "No .venv found. Create it first (README step 2)." }
$RaceTest = Join-Path $Root "data/race_test.py"
$EvidencePath = Join-Path $Root "evidence/final_validation.md"
# Local lab password; same default and override variable as docker-compose.yml.
$DbPassword = if ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { "postgres" }
$Db = "kloudkart_validate_" + (Get-Date -Format "yyyyMMddHHmmss")
$Results = New-Object System.Collections.Generic.List[object]
$Detail = New-Object System.Collections.Generic.List[string]

function Add-Result([string]$Step, [bool]$Pass, [string]$Evidence) {
    $Results.Add([pscustomobject]@{ Step = $Step; Result = $(if ($Pass) { "PASS" } else { "FAIL" }); Evidence = $Evidence })
    Write-Host ("[{0}] {1} - {2}" -f $(if ($Pass) { "PASS" } else { "FAIL" }), $Step, $Evidence)
}

function Invoke-Native {
    # Windows PowerShell 5.1 turns native stderr into errors under "Stop".
    param([scriptblock]$Command)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $Command 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }
    finally { $ErrorActionPreference = $previous }
}

function Get-MedianMs([string]$Sql) {
    $times = @()
    for ($i = 0; $i -lt 3; $i++) {
        $r = Invoke-Native { docker exec $Container psql -X -q -U postgres -d $Db -c "EXPLAIN (ANALYZE, TIMING OFF) $Sql" }
        $line = $r.Output | Where-Object { $_ -match "Execution Time: ([\d.]+) ms" } | Select-Object -Last 1
        [void]($line -match "Execution Time: ([\d.]+) ms")
        $times += [double]$Matches[1]
    }
    return ($times | Sort-Object)[1]
}

$raceHash = (Get-FileHash $RaceTest -Algorithm SHA256).Hash
Write-Host "race_test.py SHA-256: $raceHash"

try {
    # 0. Pre-flight: refuse to load CSVs whose structure has changed
    & (Join-Path $PSScriptRoot "preflight_csv.ps1") -DataDir (Join-Path $Root "data") | Out-Host
    $preflightOk = ($LASTEXITCODE -eq 0)
    Add-Result "CSV pre-flight (headers, fields, IDs, row counts)" $preflightOk $(if ($preflightOk) { "24 checks passed" } else { "see scripts/preflight_csv.ps1 output" })
    if (-not $preflightOk) { throw "CSV pre-flight failed; not loading" }

    # 1. Connection limit
    $max = [int]((Invoke-Native { docker exec $Container psql -X -At -U postgres -c "SHOW max_connections" }).Output | Select-Object -Last 1)
    Add-Result "Server allows 400-buyer test" ($max -ge 450) "max_connections = $max (need >= 450; see ADR-009)"
    if ($max -lt 450) { throw "max_connections too low; recreate the container with docker compose up -d db" }

    # 2. Fresh load + run_all (includes assertions)
    [void](Invoke-Native { docker exec $Container createdb -U postgres $Db })
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $run = Invoke-Native { docker exec $Container psql -X -q -U postgres -d $Db -v ON_ERROR_STOP=1 -v confirm_reload=yes -f /sql/run_all.sql }
    $sw.Stop()
    $oks = @($run.Output | Where-Object { $_ -match "NOTICE:  ok  " })
    $fails = @($run.Output | Where-Object { $_ -match "VALIDATION FAILED|ERROR:" })
    $Detail.Add("### run_all.sql assertions`n")
    $oks | ForEach-Object { $Detail.Add("- " + ($_ -replace '.*NOTICE:  ok  ', '')) }
    Add-Result "Fresh load + run_all.sql" ($run.Code -eq 0 -and $fails.Count -eq 0) ("exit {0} in {1:N1} s" -f $run.Code, $sw.Elapsed.TotalSeconds)
    Add-Result "Self-checking assertions" ($run.Code -eq 0 -and $oks.Count -gt 0 -and $fails.Count -eq 0) ("{0} passed, {1} failed" -f $oks.Count, $fails.Count)
    if ($run.Code -ne 0) { $run.Output | Select-Object -Last 20 | Write-Host; throw "run_all.sql failed" }

    # 3. Race test, unmodified, N times
    # Local-only connection string for the disposable database; removed below.
    $env:DATABASE_URL = "postgresql://postgres:${DbPassword}@localhost:${HostPort}/$Db"
    $passes = 0
    $walls = @()
    for ($i = 1; $i -le $RaceRuns; $i++) {
        $r = Invoke-Native { & $Python $RaceTest }
        $wall = ($r.Output | Where-Object { $_ -match "wall clock ([\d.]+)s" } | Select-Object -First 1)
        if ($wall -match "wall clock ([\d.]+)s") { $walls += $Matches[1] + " s" }
        $ok = ($r.Code -eq 0) -and ($r.Output -match "^PASSED")
        if ($ok) { $passes++ }
        $Detail.Add("`n### race_test.py run $i (exit $($r.Code))`n")
        $Detail.Add('```text')
        $r.Output | ForEach-Object { $Detail.Add($_) }
        $Detail.Add('```')
    }
    Remove-Item Env:DATABASE_URL
    Add-Result "race_test.py unmodified x$RaceRuns" ($passes -eq $RaceRuns) ("$passes/$RaceRuns passed; 400-buyer wall clock: " + ($walls -join ", "))

    # 4. Report timings
    $reportMs = Get-MedianMs "SELECT * FROM customer_spending_report(DATE '2026-08-31')"
    Add-Result "Customer report within budget" ($reportMs -lt $ReportBudgetMs) ("median {0:N0} ms for all customers (budget {1:N0} ms)" -f $reportMs, $ReportBudgetMs)
    $rollupMs = Get-MedianMs "SELECT * FROM low_stock_rollup(10)"
    Add-Result "Low-stock rollup within budget" ($rollupMs -lt $RollupBudgetMs) ("median {0:N1} ms (budget {1:N0} ms)" -f $rollupMs, $RollupBudgetMs)
}
catch {
    Add-Result "Validation run" $false "$_"
}
finally {
    if (Test-Path Env:DATABASE_URL) { Remove-Item Env:DATABASE_URL }
    [void](Invoke-Native { docker exec $Container dropdb -U postgres --if-exists $Db })

    $allPass = -not ($Results | Where-Object { $_.Result -eq "FAIL" })
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# Final end-to-end validation")
    $md.Add("")
    $md.Add("Generated by [scripts/validate_all.ps1](../scripts/validate_all.ps1) on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Disposable database ``$Db`` (dropped afterwards).")
    $md.Add("``data/race_test.py`` SHA-256 ``$raceHash`` (unmodified supplied file).")
    $md.Add("")
    $md.Add("**Overall: $(if ($allPass) { 'PASS' } else { 'FAIL' })**")
    $md.Add("")
    $md.Add("| Step | Result | Evidence |")
    $md.Add("|---|---|---|")
    $Results | ForEach-Object { $md.Add("| $($_.Step) | $($_.Result) | $($_.Evidence) |") }
    $md.Add("")
    $Detail | ForEach-Object { $md.Add($_) }
    $md | Set-Content -Path $EvidencePath -Encoding utf8
    Write-Host "Evidence written to $EvidencePath"
    if (-not $allPass) { exit 1 }
}

<#
.SYNOPSIS
  Before/after performance evidence for the Monday report and the low-stock rollup.

.DESCRIPTION
  Creates a disposable database, loads the ORIGINAL supplied schema (no indexes),
  and measures, each as the median of -Runs executions using EXPLAIN ANALYZE:

    1. Naive "before" report on 500 / 1,000 / 2,000 customers  (original schema)
    2. New set-based report, full 40,420 customers              (original schema, no indexes)
    3. Low-stock rollup: fixed-depth naive vs recursive         (original schema)
    4. Indexes applied (sql/02_schema_changes/03_indexes.sql), then:
       naive report at full size, new report, rollup
    5. Depth-5 correctness demo (rolled back)

  Raw output goes to evidence/benchmark_raw.txt. The database is dropped at the end.
  Use -FullNaiveBaseline to also run the full naive report on the original schema
  (expected to take tens of minutes; capped by -FullTimeoutMinutes).

.EXAMPLE
  .\scripts\benchmark.ps1
  .\scripts\benchmark.ps1 -FullNaiveBaseline -FullTimeoutMinutes 60
#>
param(
    [int]$Runs = 3,
    [int[]]$Samples = @(500, 1000, 2000),
    [switch]$FullNaiveBaseline,
    [int]$FullTimeoutMinutes = 60,
    [string]$Container = "kloudkart-db"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$RawPath = Join-Path $Root "evidence\benchmark_raw.txt"
$Db = "kloudkart_bench_" + (Get-Date -Format "yyyyMMddHHmmss")
$Raw = New-Object System.Collections.Generic.List[string]

function Write-Raw([string]$Line) {
    Write-Host $Line
    $Raw.Add($Line)
}

function Invoke-Psql {
    param([string[]]$PsqlArgs)
    # Windows PowerShell 5.1 turns native stderr (psql NOTICEs) into errors
    # under "Stop"; rely on psql's exit code instead.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & docker exec $Container psql -X -q -U postgres -d $Db -v ON_ERROR_STOP=1 @PsqlArgs 2>&1 |
            ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "psql failed: $($out -join "`n")" }
    return $out
}

function Get-ExecMs {
    param([string]$Label, [string[]]$PsqlArgs)
    $times = @()
    for ($i = 1; $i -le $Runs; $i++) {
        $out = Invoke-Psql $PsqlArgs
        $line = $out | Where-Object { $_ -match "Execution Time: ([\d.]+) ms" } | Select-Object -Last 1
        if (-not $line) { throw "No Execution Time for $Label" }
        [void]($line -match "Execution Time: ([\d.]+) ms")
        $times += [double]$Matches[1]
    }
    $sorted = $times | Sort-Object
    $median = $sorted[[int][math]::Floor($sorted.Count / 2)]
    Write-Raw ("{0,-62} median {1,12:N1} ms   runs: {2}" -f $Label, $median, (($times | ForEach-Object { "{0:N1}" -f $_ }) -join ", "))
    return $median
}

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$pg = (& docker exec $Container psql -X -At -U postgres -c "SELECT version()").Trim()
Write-Raw "Benchmark run $(Get-Date -Format 's')"
Write-Raw "Host: $cpu, $ram GB RAM; Docker container $Container"
Write-Raw "Server: $pg"
Write-Raw "Database: $Db (disposable, dropped afterwards); median of $Runs runs"
Write-Raw ""

& docker exec $Container createdb -U postgres $Db
if ($LASTEXITCODE -ne 0) { throw "createdb failed" }

try {
    Write-Raw "== Original schema (supplied schema.sql + load.sql, primary keys only) =="
    Invoke-Psql @("-c", "\cd /", "-f", "/data/schema.sql", "-f", "/data/load.sql") | Out-Null

    $naive = @{}
    foreach ($n in $Samples) {
        $naive[$n] = Get-ExecMs "naive report, $n customers, no indexes" @("-v", "sample=$n", "-f", "/sql/00_baseline/04_naive_report_sample.sql")
    }
    $perCustomer = ($Samples | ForEach-Object { $naive[$_] / $_ } | Measure-Object -Average).Average
    $customers = [int]((Invoke-Psql @("-At", "-c", "SELECT count(*) FROM customers")) | Select-Object -Last 1)
    Write-Raw ("naive report, extrapolated to {0:N0} customers            ~ {1:N0} s (~{2:N1} min) at {3:N2} ms/customer" -f $customers, ($perCustomer * $customers / 1000), ($perCustomer * $customers / 60000), $perCustomer)

    Invoke-Psql @("-f", "/sql/04_reporting/customer_spending_report.sql", "-f", "/sql/04_reporting/low_stock_rollup.sql") | Out-Null
    Get-ExecMs "new report, all customers, no indexes" @("-c", "EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM customer_spending_report(DATE '2026-08-31')") | Out-Null
    Get-ExecMs "recursive rollup, no indexes" @("-c", "EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM low_stock_rollup(10)") | Out-Null
    Get-ExecMs "fixed-depth (naive) rollup, no indexes" @("-f", "/sql/00_baseline/05_naive_rollup_fixed_depth.sql", "-c", "EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM pg_temp.naive_low_stock_rollup") | Out-Null

    if ($FullNaiveBaseline) {
        Write-Raw ""
        Write-Raw "== Full naive report on original schema (timeout $FullTimeoutMinutes min) =="
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ErrorActionPreference = "Continue"
        $out = & docker exec $Container psql -X -q -U postgres -d $Db -c "SET statement_timeout = '${FullTimeoutMinutes}min'" -v sample=1000000 -f /sql/00_baseline/04_naive_report_sample.sql 2>&1 |
            ForEach-Object { "$_" }
        $ErrorActionPreference = "Stop"
        $sw.Stop()
        $line = $out | Where-Object { $_ -match "Execution Time" } | Select-Object -Last 1
        if ($line) { Write-Raw "naive report, all customers, no indexes: $($line.Trim())" }
        else { Write-Raw ("naive report, all customers, no indexes: did not finish; stopped after {0:N1} min ({1})" -f $sw.Elapsed.TotalMinutes, (($out | Select-Object -Last 1) -join ' ')) }
    }

    Write-Raw ""
    Write-Raw "== After sql/02_schema_changes/03_indexes.sql =="
    Invoke-Psql @("-f", "/sql/02_schema_changes/03_indexes.sql", "-c", "ANALYZE") | Out-Null
    Get-ExecMs "naive report, all customers, WITH indexes" @("-v", "sample=1000000", "-f", "/sql/00_baseline/04_naive_report_sample.sql") | Out-Null
    Get-ExecMs "new report, all customers, WITH indexes" @("-c", "EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM customer_spending_report(DATE '2026-08-31')") | Out-Null
    Get-ExecMs "recursive rollup, WITH indexes" @("-c", "EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM low_stock_rollup(10)") | Out-Null

    Write-Raw ""
    Write-Raw "== Depth-5 correctness demo (rolled back) =="
    $demo = Invoke-Psql @("-f", "/sql/00_baseline/05_naive_rollup_fixed_depth.sql", "-f", "/sql/00_baseline/06_rollup_depth5_demo.sql")
    $demo | Where-Object { $_ -and $_ -notmatch "^(BEGIN|ROLLBACK|SELECT|INSERT|UPDATE|CREATE)" } | ForEach-Object { Write-Raw $_ }
}
catch {
    Write-Raw "BENCHMARK FAILED: $_"
    throw
}
finally {
    $ErrorActionPreference = "Continue"
    & docker exec $Container dropdb -U postgres --if-exists $Db 2>&1 | Out-Null
    $Raw | Set-Content -Path $RawPath -Encoding utf8
    Write-Host "Raw output written to $RawPath"
}

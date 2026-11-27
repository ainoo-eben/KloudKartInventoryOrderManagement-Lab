<#
.SYNOPSIS
  Reproduces the overselling race with a deliberately unsafe check-then-update.

.DESCRIPTION
  Creates the throwaway schema kloudkart_baseline_race in -DbName, fires two
  concurrent "buy the last unit" attempts, checks that both succeed and stock
  ends at -1 (the bug), then drops the schema. It never touches the solution
  tables. Never use the fixture function to place real orders.

  -DbName is required, so the script cannot silently target the wrong
  database. Use the disposable database created in the root README.

.EXAMPLE
  .\scripts\run_baseline_race.ps1 -DbName $DbName
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
    [string]$DbName,
    [string]$Container = "kloudkart-db"
)

$ErrorActionPreference = 'Stop'

$schema = 'kloudkart_baseline_race'
$schemaCreated = $false
$jobs = @()

$exists = docker exec $Container psql -X -At -U postgres -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '$DbName'"
if ($LASTEXITCODE -ne 0 -or "$exists".Trim() -ne '1') {
    throw "Database '$DbName' does not exist in container '$Container'. Create a disposable one first (see README step 4)."
}

try {
    docker exec $Container psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/00_baseline/03_reproduce_oversell.sql
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to prepare the isolated race fixture.'
    }
    $schemaCreated = $true

    for ($i = 0; $i -lt 2; $i++) {
        $jobs += Start-Job -ArgumentList $Container, $DbName -ScriptBlock {
            param($Container, $DbName)
            docker exec $Container psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -At -c "SELECT kloudkart_baseline_race.try_order(1);"
            if ($LASTEXITCODE -ne 0) {
                throw 'A concurrent baseline order attempt failed.'
            }
        }
    }

    Wait-Job -Job $jobs | Out-Null
    foreach ($job in $jobs) {
        $attemptOutput = Receive-Job -Job $job
        if ($attemptOutput) {
            Write-Output $attemptOutput
        }
        if ($job.State -ne 'Completed') {
            throw 'A concurrent baseline order attempt did not complete successfully.'
        }
    }

    $summary = docker exec $Container psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -At -F '|' -c "SELECT count(*) FILTER (WHERE outcome = 'success'), (SELECT stock_quantity FROM kloudkart_baseline_race.stock_fixture WHERE product_id = 1) FROM kloudkart_baseline_race.attempts WHERE product_id = 1;"
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the baseline race results.'
    }

    Write-Output "successful_attempts|final_stock"
    Write-Output $summary
    if ($summary.Trim() -ne '2|-1') {
        throw "Expected two successful attempts and final stock -1; got '$summary'."
    }
}
finally {
    if ($jobs.Count -gt 0) {
        foreach ($job in $jobs) {
            if ($job.State -eq 'Running' -or $job.State -eq 'NotStarted') {
                Wait-Job -Job $job | Out-Null
            }
            if ($job.State -ne 'Running') {
                Remove-Job -Job $job -Force
            }
        }
    }

    if ($schemaCreated) {
        docker exec $Container psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -c "SET client_min_messages = warning; DROP SCHEMA $schema CASCADE;"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to remove the temporary schema $schema."
        }
    }
}

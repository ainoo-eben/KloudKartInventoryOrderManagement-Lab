$ErrorActionPreference = 'Stop'

$schema = 'kloudkart_baseline_race'
$schemaCreated = $false
$jobs = @()

try {
    docker exec kloudkart-db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -f /sql/00_baseline/03_reproduce_oversell.sql
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to prepare the isolated race fixture.'
    }
    $schemaCreated = $true

    for ($i = 0; $i -lt 2; $i++) {
        $jobs += Start-Job -ScriptBlock {
            docker exec kloudkart-db psql -X -U postgres -d kloudkart -v ON_ERROR_STOP=1 -At -c "SELECT kloudkart_baseline_race.try_order(1);"
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

    $summary = docker exec kloudkart-db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -At -F '|' -c "SELECT count(*) FILTER (WHERE outcome = 'success'), (SELECT stock_quantity FROM kloudkart_baseline_race.stock_fixture WHERE product_id = 1) FROM kloudkart_baseline_race.attempts WHERE product_id = 1;"
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
        docker exec kloudkart-db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -c "SET client_min_messages = warning; DROP SCHEMA $schema CASCADE;"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to remove the temporary schema $schema."
        }
    }
}

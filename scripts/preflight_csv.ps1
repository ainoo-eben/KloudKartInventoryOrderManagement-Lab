<#
.SYNOPSIS
  Pre-flight check of the six supplied CSVs before they are loaded.

.DESCRIPTION
  data/load.sql uses \copy ... HEADER true, which maps columns by POSITION and
  skips the header line without reading it. So a re-exported CSV whose columns
  are reordered (for example price <-> stock_quantity, both numbers) would load
  without any error and silently corrupt every report. A truncated export would
  also load "successfully". This script catches those cases before loading:

    1. File exists and is not empty.
    2. Header matches the column list load.sql expects, in the same order.
    3. Every row has exactly as many fields as the header (real CSV parsing,
       so quoted commas and line breaks inside fields are handled).
    4. The first column (the ID) is a whole number on every row.
    5. Row count is at least -MinRowRatio of the supplied extract's count
       (catches truncated or partial exports; growth is fine).

  It only reads the files; it never modifies data/. Exit code 0 = safe to load.

.EXAMPLE
  .\scripts\preflight_csv.ps1
  .\scripts\preflight_csv.ps1 -DataDir D:\new_extract -MinRowRatio 0.95
#>
param(
    [string]$DataDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "data"),
    [ValidateRange(0.0, 1.0)]
    [double]$MinRowRatio = 0.9
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic

# Column lists copied from data/load.sql (the order \copy will use) and the
# row counts of the supplied extract (evidence/row_counts_before.md).
$Expected = [ordered]@{
    "categories.csv"    = @{ Columns = "category_id,category_name,parent_id"; Rows = 94 }
    "products.csv"      = @{ Columns = "product_id,product_name,category_id,price,stock_quantity,created_at"; Rows = 4023 }
    "customers.csv"     = @{ Columns = "customer_id,full_name,email,phone,city,registered_at"; Rows = 40420 }
    "orders.csv"        = @{ Columns = "order_id,customer_id,order_date,status,total_amount"; Rows = 159384 }
    "order_items.csv"   = @{ Columns = "order_item_id,order_id,product_id,quantity,unit_price"; Rows = 336559 }
    "inventory_log.csv" = @{ Columns = "log_id,product_id,change_qty,reason,created_at,note"; Rows = 282352 }
}

$Results = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$File, [string]$Check, [bool]$Pass, [string]$Detail) {
    $Results.Add([pscustomobject]@{
        File = $File; Check = $Check
        Result = $(if ($Pass) { "PASS" } else { "FAIL" }); Detail = $Detail
    })
}

foreach ($name in $Expected.Keys) {
    $spec = $Expected[$name]
    $path = Join-Path $DataDir $name
    $expectedCols = $spec.Columns.Split(",")

    if (-not (Test-Path $path -PathType Leaf)) {
        Add-Check $name "exists" $false "not found in $DataDir"
        continue
    }
    if ((Get-Item $path).Length -eq 0) {
        Add-Check $name "exists" $false "file is empty"
        continue
    }

    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($path, [System.Text.Encoding]::UTF8)
    try {
        $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
        $parser.SetDelimiters(",")
        $parser.HasFieldsEnclosedInQuotes = $true
        $parser.TrimWhiteSpace = $false

        # 2. Header: same names, same order (BOM and surrounding spaces ignored).
        $header = @($parser.ReadFields() | ForEach-Object { $_.Trim().TrimStart([char]0xFEFF).ToLowerInvariant() })
        $headerOk = ($header -join ",") -eq $spec.Columns
        $headerDetail = if ($headerOk) { "$($header.Count) columns in load.sql order" } else {
            "expected '$($spec.Columns)' but found '$($header -join ",")'"
        }
        Add-Check $name "header matches load.sql" $headerOk $headerDetail

        # 3-4. Every row: field count and integer ID.
        $rows = 0
        $badWidth = 0; $firstBadWidth = $null
        $badId = 0; $firstBadId = $null
        while (-not $parser.EndOfData) {
            $line = $parser.LineNumber
            try { $fields = $parser.ReadFields() }
            catch [Microsoft.VisualBasic.FileIO.MalformedLineException] {
                $rows++; $badWidth++
                if ($null -eq $firstBadWidth) { $firstBadWidth = "line $line is malformed (unbalanced quotes?)" }
                continue
            }
            $rows++
            if ($fields.Count -ne $expectedCols.Count) {
                $badWidth++
                if ($null -eq $firstBadWidth) { $firstBadWidth = "line $line has $($fields.Count) fields" }
            }
            [long]$id = 0
            if (-not [long]::TryParse($fields[0], [ref]$id)) {
                $badId++
                if ($null -eq $firstBadId) { $firstBadId = "line $line has '$($fields[0])'" }
            }
        }

        Add-Check $name "every row has $($expectedCols.Count) fields" ($badWidth -eq 0) $(
            if ($badWidth -eq 0) { "$rows rows checked" } else { "$badWidth bad rows; first: $firstBadWidth" })
        Add-Check $name "$($expectedCols[0]) is a whole number" ($badId -eq 0) $(
            if ($badId -eq 0) { "all $rows rows" } else { "$badId bad rows; first: $firstBadId" })

        # 5. Not truncated.
        $floor = [math]::Ceiling($spec.Rows * $MinRowRatio)
        Add-Check $name "row count >= $floor" ($rows -ge $floor) ("{0:N0} rows (supplied extract: {1:N0})" -f $rows, $spec.Rows)
    }
    finally {
        $parser.Close()
    }
}

$Results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$failed = @($Results | Where-Object { $_.Result -eq "FAIL" })
if ($failed.Count -gt 0) {
    Write-Host "PRE-FLIGHT FAILED: $($failed.Count) check(s). Do not load these files until fixed." -ForegroundColor Red
    exit 1
}
Write-Host "PRE-FLIGHT PASSED: all $($Results.Count) checks. Safe to load." -ForegroundColor Green
exit 0

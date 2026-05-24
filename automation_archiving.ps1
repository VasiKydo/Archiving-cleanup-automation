
$Root = "C:\Reports"
$ArchivePath = "C:\Reports\Archive"
$KeepLatest = 5


$now = Get-Date
$dailyCutoff   = $now.AddDays(-7)
$weeklyCutoff  = $now.AddDays(-35)
$monthlyCutoff = $now.AddMonths(-5)

# Exit if archive path does not exist
if (-not (Test-Path $ArchivePath)) {
    Write-Host "Archive path not found."
    return
}

# Store grouped file data
$filesData = @{}

# Example filename format:
# reportA_20260522.csv
# reportA_20260521.csv
# reportA_20260521.txt

$files = Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue

foreach ($f in $files) {

    $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $ext  = $f.Extension.ToLower()

    # Ensure filename contains at least 8 chars for yyyyMMdd
    if ($base.Length -lt 8) {
        continue
    }

    $ymd = $base.Substring($base.Length - 8, 8)

    # Validate date pattern
    if (-not ($ymd -match '^\d{8}$')) {
        continue
    }

    $prefix = $base.Substring(0, $base.Length - 8)

    try {
        $date = [datetime]::ParseExact(
            $ymd,
            'yyyyMMdd',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        continue
    }

    # Group by filename prefix + extension
    $key = "$prefix|$ext"

    if (-not $filesData.ContainsKey($key)) {
        $filesData[$key] = @{
            Prefix = $prefix
            Ext    = $ext
            Items  = New-Object System.Collections.ArrayList
        }
    }

}

if ($filesData.Count -eq 0) {
    Write-Host "No matching files found."
    return
}

foreach ($entry in $filesData.GetEnumerator()) {

    $list = $entry.Value.Items

    if ($list.Count -eq 0) {
        continue
    }

    # Sort newest first
    $sorted = $list | Sort-Object Date -Descending

    $latest1 = $sorted[0].Date
    $latest2 = if ($sorted.Count -gt 1) {
        $sorted[1].Date
    }
    else {
        $null
    }

    # Detect frequency automatically
    $frequency = 'daily'

    if ($latest2) {

        $gap = [int]([timespan]($latest1 - $latest2)).TotalDays

        if ($gap -le 3) {
            $frequency = 'daily'
        }
        elseif ($gap -le 13) {
            $frequency = 'weekly'
        }
        else {
            $frequency = 'monthly'
        }
    }

    # Select retention cutoff
    $cutoff = switch ($frequency) {
        'daily'   { $dailyCutoff }
        'weekly'  { $weeklyCutoff }
        'monthly' { $monthlyCutoff }
        default   { $dailyCutoff }
    }

    # Always keep latest files
    $filesToKeep = $sorted | Select-Object -First $KeepLatest

    # Archive older files
    $filesToMove = $sorted | Where-Object {
        ($filesToKeep -notcontains $_)
    }

    foreach ($item in $filesToMove) {

        $destination = Join-Path $ArchivePath $item.File.Name

        move-item -literalPath $item.File.FullName -Destination $destination -ErrorAction SilentlyContinue
    }
}
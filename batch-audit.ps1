# batch-audit.ps1 — Run 30 website audits sequentially
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$audits = @(
  # Existing businesses (re-audit)
  @{name="The Castlecourt Hotel"; url="https://www.castlecourthotel.ie/"; loc="Westport"; type="hotel"}
  @{name="Hotel Westport"; url="https://www.hotelwestport.ie/"; loc="Westport"; type="hotel"}
  @{name="Knockranny House Hotel"; url="https://www.knockrannyhousehotel.ie/"; loc="Westport"; type="hotel"}
  # Westport remaining (7)
  @{name="The Wyatt Hotel"; url="https://www.wyatthotel.com/"; loc="Westport"; type="hotel"}
  @{name="Westport Heights Hotel"; url="https://www.westportheights.com/"; loc="Westport"; type="hotel"}
  @{name="Sheaffrey's Bar & Townhouse"; url="https://www.sheaffreys.com/"; loc="Westport"; type="hotel"}
  @{name="Plougastel-Daoulas Restaurant"; url="https://plougastel-daoulas.ie/"; loc="Westport"; type="restaurant"}
  @{name="Sage Restaurant Westport"; url="https://sagewestport.ie/"; loc="Westport"; type="restaurant"}
  @{name="An Port Mor Restaurant"; url="https://www.anportmor.ie/"; loc="Westport"; type="restaurant"}
  @{name="The West Coast Hotel"; url="https://www.westcoasthotel.ie/"; loc="Westport"; type="hotel"}
  # Galway (10)
  @{name="The g Hotel"; url="https://www.theghotel.ie/"; loc="Galway"; type="hotel"}
  @{name="Galmont Hotel & Spa"; url="https://www.galmont.ie/"; loc="Galway"; type="hotel"}
  @{name="The Hardiman Hotel"; url="https://www.thehardiman.ie/"; loc="Galway"; type="hotel"}
  @{name="The House Hotel"; url="https://www.thehousehotel.ie/"; loc="Galway"; type="hotel"}
  @{name="Oranmore Lodge Hotel"; url="https://www.oranmorelodge.ie/"; loc="Galway"; type="hotel"}
  @{name="The Twelve Hotel"; url="https://www.thetwelvehotel.ie/"; loc="Galway"; type="hotel"}
  @{name="Glenlo Abbey Hotel & Estate"; url="https://www.glenloabbey.ie/"; loc="Galway"; type="hotel"}
  @{name="Jurys Inn Galway"; url="https://www.jurysinnsgalway.com/"; loc="Galway"; type="hotel"}
  @{name="Flannery's Hotel Galway"; url="https://www.flanneryshotelgalway.ie/"; loc="Galway"; type="hotel"}
  @{name="Salthill Hotel"; url="https://www.salthillhotel.com/"; loc="Galway"; type="hotel"}
  # Sligo (10)
  @{name="Sligo Park Hotel"; url="https://www.sligoparkhotel.ie/"; loc="Sligo"; type="hotel"}
  @{name="The Glasshouse Hotel"; url="https://www.theglasshousehotel.ie/"; loc="Sligo"; type="hotel"}
  @{name="Radisson Blu Hotel & Spa Sligo"; url="https://www.radissonblu.com/"; loc="Sligo"; type="hotel"}
  @{name="Clayton Hotel Sligo"; url="https://www.claytonsligo.ie/"; loc="Sligo"; type="hotel"}
  @{name="Yeats Country Hotel, Spa & Leisure Club"; url="https://www.yeatscountryhotel.com/"; loc="Sligo"; type="hotel"}
  @{name="The Diamond Coast Hotel"; url="https://www.diamondcoast.ie/"; loc="Sligo"; type="hotel"}
  @{name="Belleek Castle & Thatch Bar"; url="https://www.belleekcastle.ie/"; loc="Sligo"; type="hotel"}
  @{name="Riverside Hotel Sligo"; url="https://www.riversidehotelsligo.com/"; loc="Sligo"; type="hotel"}
  @{name="Moran's Bar & Restaurant"; url="https://www.moranssligo.ie/"; loc="Sligo"; type="restaurant"}
  @{name="The Coach House Hotel"; url="https://www.thecoachhousehotelsligo.ie/"; loc="Sligo"; type="hotel"}
)

$total = $audits.Count
$done = 0
$failed = @()

$logFile = Join-Path $PSScriptRoot "batch-audit-log.txt"
$line = "BATCH AUDIT LOG - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$line | Out-File -Encoding utf8 $logFile
"Total: $total sites" | Out-File -Encoding utf8 -Append $logFile
"" | Out-File -Encoding utf8 -Append $logFile

foreach ($a in $audits) {
  $done++
  $pct = [math]::Round($done / $total * 100, 0)
  $start = Get-Date
  Write-Host ""
  Write-Host "====================================" -ForegroundColor Cyan
  Write-Host "  [$done/$total] $pct% - $($a.name)" -ForegroundColor White
  Write-Host "  $($a.loc) | $($a.type)" -ForegroundColor Gray
  Write-Host "  $($a.url)" -ForegroundColor Gray
  Write-Host "====================================" -ForegroundColor Cyan

  try {
    $output = & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\analyze.ps1" `
      -Url $a.url -BusinessName $a.name -Location $a.loc -BusinessType $a.type -SkipScreenshot 2>&1

    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
    Write-Host "  Completed in ${elapsed}s" -ForegroundColor Green

    $logLine = "[$done/$total] DONE: $($a.name) in ${elapsed}s"
    $logLine | Out-File -Encoding utf8 -Append $logFile
  } catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $failed += $a.name
    $failLine = "FAILED: $($a.name) - $($_.Exception.Message)"
    $failLine | Out-File -Encoding utf8 -Append $logFile
  }

  Start-Sleep -Seconds 1
}

# Summary
Write-Host ""
Write-Host "====================================" -ForegroundColor Green
Write-Host "  BATCH COMPLETE" -ForegroundColor Green
Write-Host "  $done of $total sites audited" -ForegroundColor White
if ($failed.Count -gt 0) {
  Write-Host "  Failed: $($failed.Count)" -ForegroundColor Red
  foreach ($f in $failed) { Write-Host "    - $f" -ForegroundColor Red }
}
Write-Host "====================================" -ForegroundColor Green

"========================================" | Out-File -Encoding utf8 -Append $logFile
$completeLine = "BATCH COMPLETE at $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$completeLine | Out-File -Encoding utf8 -Append $logFile
"Total: $done/$total - Failed: $($failed.Count)" | Out-File -Encoding utf8 -Append $logFile

# batch-audit-v2.ps1 — Run website audits, prechecking each site first
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$audits = @(
  @{name="The Castlecourt Hotel"; url="https://www.castlecourthotel.ie/"; loc="Westport"; type="hotel"}
  @{name="Hotel Westport"; url="https://www.hotelwestport.ie/"; loc="Westport"; type="hotel"}
  @{name="Knockranny House Hotel"; url="https://www.knockrannyhousehotel.ie/"; loc="Westport"; type="hotel"}
  @{name="The Wyatt Hotel"; url="https://www.wyatthotel.com/"; loc="Westport"; type="hotel"}
  @{name="Westport Heights Hotel"; url="https://www.westportheights.com/"; loc="Westport"; type="hotel"}
  @{name="Sheaffrey's Bar & Townhouse"; url="https://www.sheaffreys.com/"; loc="Westport"; type="hotel"}
  @{name="Plougastel-Daoulas Restaurant"; url="https://plougastel-daoulas.ie/"; loc="Westport"; type="restaurant"}
  @{name="Sage Restaurant Westport"; url="https://sagewestport.ie/"; loc="Westport"; type="restaurant"}
  @{name="An Port Mor Restaurant"; url="https://www.anportmor.ie/"; loc="Westport"; type="restaurant"}
  @{name="The West Coast Hotel"; url="https://www.westcoasthotel.ie/"; loc="Westport"; type="hotel"}
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

function PreCheckSite {
  param($url)
  try {
    $raw = curl.exe -s -o NUL -w "%{http_code}" -A "Mozilla/5.0" --connect-timeout 8 --max-time 10 $url 2>&1
    $code = ($raw | Select-Object -Last 1).Trim()
    # Only accept proper HTTP codes (200-599). Reject 000 (DNS/connection failure)
    if ($code -match "^[2-5]\d\d$") { return $true }
    return $false
  } catch { return $false }
}

$total = $audits.Count
$audited = 0
$failed = 0
$skipped = 0

$logFile = Join-Path $PSScriptRoot "batch-audit-log.txt"
$line = "BATCH AUDIT v2 - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$line | Out-File -Encoding utf8 $logFile
"Total: $total prospects" | Out-File -Encoding utf8 -Append $logFile
"" | Out-File -Encoding utf8 -Append $logFile

$completedReport = @()

foreach ($a in $audits) {
  $done = $audited + $failed + $skipped
  $pct = [math]::Round(($done + 1) / $total * 100, 0)
  $start = Get-Date

  Write-Host ""
  Write-Host "====================================" -ForegroundColor Cyan
  Write-Host "  [$($done+1)/$total] $pct% - $($a.name)" -ForegroundColor White
  Write-Host "  $($a.loc) | $($a.type) | $($a.url)" -ForegroundColor Gray
  Write-Host "====================================" -ForegroundColor Cyan

  Write-Host "  Pre-checking..." -ForegroundColor Yellow
  $reachable = PreCheckSite $a.url

  if (-not $reachable) {
    Write-Host "  SITE UNREACHABLE" -ForegroundColor Red

    # Create a minimal "site down" report
    $id = -join ((48..57)+(97..102) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    $downReport = @{
      id = $id
      businessName = $a.name
      url = $a.url
      score = 0
      analyzedAt = (Get-Date -Format "yyyy-MM-dd HH:mm")
      location = $a.loc
      businessType = $a.type
      platform = ""
      benchmark = ""
      critical = 0
      high = 0
      medium = 0
      low = 0
      issues = @(@{
        type = "business"
        label = "Website is offline or unreachable"
        severity = "critical"
        detail = "The website at $($a.url) could not be reached. This is the most critical issue a business can have."
        check = "Try visiting $($a.url) in a browser. If it doesn't load, the site is down."
        siteHint = "If your website is down, you are losing customers. Contact your hosting provider immediately."
      })
      positives = @()
    }

    if (-not (Test-Path "reports")) { New-Item -ItemType Directory "reports" -Force | Out-Null }
    $downReport | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 "reports/$id.json"

    # Generate a minimal HTML report
    $simpleHtml = @"
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>SITE DOWN - $($a.name) - DS Studios</title>
<meta name="robots" content="noindex,nofollow">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Inter',sans-serif;background:#f4f5f9;color:#1a202c;text-align:center;padding:60px 20px}
.card{background:#fff;border-radius:16px;padding:40px;max-width:500px;margin:0 auto;box-shadow:0 2px 8px rgba(0,0,0,.06)}
.icon{font-size:48px;margin-bottom:16px}
h1{font-size:20px;margin-bottom:8px}
p{color:#6b7280;font-size:13px;line-height:1.6;margin-bottom:12px}
.badge{display:inline-block;background:#ef4444;color:#fff;padding:6px 16px;border-radius:20px;font-size:14px;font-weight:700;margin:8px}
.footer{margin-top:24px;font-size:10px;color:#9ca3af}
.footer a{color:#a3d977;text-decoration:none}
</style></head>
<body>
<div class="card">
  <div class="icon">⚠️</div>
  <h1>$($a.name)</h1>
  <div class="badge">0/100</div>
  <p>This website could not be reached. The site may be offline, have DNS issues, or be blocking connections.<br><br>
  <a href="$($a.url)" style="color:#a3d977">$($a.url)</a><br><br>
  <strong>Location:</strong> $($a.loc) | <strong>Type:</strong> $($a.type)</p>
</div>
<div class="footer"><a href="https://dsstudios.ie">DS Studios</a> — Websites for small businesses in Ireland</div>
</body></html>
"@
    $simpleHtml | Out-File -Encoding utf8 "reports/$id.html"

    # Log to analytics
    $logEntry = @{
      id=$id
      businessName=$a.name
      url=$a.url
      score=0
      location=$a.loc
      businessType=$a.type
      analyzedAt=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
      critical=1
      high=0
      medium=0
      low=0
      totalIssues=1
      totalPositives=0
      platform=""
    }
    $logDir = Join-Path $PSScriptRoot "analytics"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logEntry | ConvertTo-Json -Compress -Depth 3 | Out-File -Encoding utf8 -Append (Join-Path $logDir "audit-log.jsonl")

    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
    Write-Host "  Skipped (site down) in ${elapsed}s" -ForegroundColor DarkYellow
    "SKIPPED (DOWN): $($a.name)" | Out-File -Encoding utf8 -Append $logFile
    $skipped++
    continue
  }

  Write-Host "  Site reachable, auditing..." -ForegroundColor Green

  try {
    $output = & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\analyze.ps1" `
      -Url $a.url -BusinessName $a.name -Location $a.loc -BusinessType $a.type -SkipScreenshot 2>&1

    # Check exit code
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  Process exited with code $LASTEXITCODE" -ForegroundColor Red
    }

    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
    Write-Host "  Completed in ${elapsed}s" -ForegroundColor Green
    "DONE: $($a.name) in ${elapsed}s" | Out-File -Encoding utf8 -Append $logFile
    $audited++
  } catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    "FAILED: $($a.name) - $($_.Exception.Message)" | Out-File -Encoding utf8 -Append $logFile
    $failed++
  }

  # Collect score from the last JSON report
  $latestJson = Get-ChildItem "reports" -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latestJson) {
    $r = Get-Content $latestJson.FullName -Raw | ConvertFrom-Json
    $completedReport += @{ name=$r.businessName; score=$r.score; loc=$r.location; issues=$r.totalIssues; platform=$r.platform }
  }

  Start-Sleep -Seconds 1
}

# Summary
Write-Host ""
Write-Host "====================================" -ForegroundColor Green
Write-Host "  BATCH AUDIT COMPLETE" -ForegroundColor Green
Write-Host "  Total: $total prospects" -ForegroundColor White
Write-Host "  Audited: $audited" -ForegroundColor Green
Write-Host "  Skipped (down): $skipped" -ForegroundColor DarkYellow
Write-Host "  Failed: $failed" -ForegroundColor Red
Write-Host "====================================" -ForegroundColor Green

"========================================" | Out-File -Encoding utf8 -Append $logFile
"BATCH COMPLETE at $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-File -Encoding utf8 -Append $logFile
"Audited: $audited | Skipped (down): $skipped | Failed: $failed" | Out-File -Encoding utf8 -Append $logFile

# Write completion report
$result = $completedReport | ConvertTo-Json -Depth 3
$result | Out-File -Encoding utf8 (Join-Path $PSScriptRoot "reports" "batch-complete.json")

Write-Host ""
Write-Host "RESULTS:" -ForegroundColor Cyan
foreach ($r in $completedReport) {
  $color = if ($r.score -ge 70) { "Green" } elseif ($r.score -ge 40) { "Yellow" } else { "Red" }
  Write-Host "  $($r.name): $($r.score)/100 ($($r.loc)) - $($r.platform)" -ForegroundColor $color
}

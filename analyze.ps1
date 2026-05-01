param(
  [Parameter(Mandatory=$true)]
  [string]$Url,
  [string]$BusinessName = "",
  [string]$OutputDir = "reports",
  [switch]$SkipScreenshot,
  [switch]$SkipVisual
)

$ErrorActionPreference = "Stop"
$id = -join ((48..57)+(97..102) | Get-Random -Count 8 | ForEach-Object {[char]$_})
$name = if($BusinessName -ne ""){$BusinessName}else{$url -replace 'https?://','' -replace 'www\.','' -replace '/.*$',''}

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  DS STUDIOS - Website Audit" -ForegroundColor Green
Write-Host "  $name" -ForegroundColor White
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# ---- PART 1: HTML Analysis ----
Write-Host 'Phase 1: HTML source analysis...' -ForegroundColor Yellow

try {
  $wc = New-Object System.Net.WebClient
  $wc.Headers.Add("User-Agent","Mozilla/5.0 Windows Chrome 120")
  $html = $wc.DownloadString($url)
  $pageSize = $html.Length
} catch {
  Write-Host "ERROR: Could not fetch $url" -ForegroundColor Red
  exit 1
}

$issues = @()
$positives = @()
$vIssues = @()
$vPositives = @()

function AddIssue($t,$l,$s,$d,$c,$h){
  $global:issues += @{type=$t;label=$l;severity=$s;detail=$d;check=$c;siteHint=$h}
}
function AddPos($d){$global:positives += @{detail=$d}}

# Pre-defined patterns
$patTitle  = '<title[^>]*>(.*?)<'
$patMeta   = 'name="?description"?'
$patVP     = 'name="?viewport"?'
$patH1     = '<h1'
$patForm   = '<form'
$patNav    = '<nav'
$patSchema = 'itemscope|itemtype|application/ld'
$patAnal   = 'gtag|google-analytics|fbevents|clarity|hotjar|analytics'
$patHTTP   = '(src|href)="http://[^"]+"'
$patIMG    = '<img[^>]*>'
$patAlt    = '<img[^>]+alt[= ]'
$patCSS    = '<link[^>]+rel="stylesheet"[^>]*href="([^"]+)"'
$patStyle  = '<style[^>]*>'
$patScript = '<script[^>]*src="[^"]*"'

# Title
$hasTitle = $html -match $patTitle
$titleText = if($hasTitle){$matches[1].Trim()}else{"MISSING"}
if(-not $hasTitle){
  AddIssue "seo" "Missing page title" "high" "Your page title tag is missing. This appears in search results and browser tabs." "Open the page. Look at the browser tab text. If it says the URL or 'Home' instead of your business name, it is missing." "Google may show your URL instead of a proper title in search results."
} else { AddPos "Page title is set" }

# Meta description
$hasMeta = $html -match $patMeta
if(-not $hasMeta){
  AddIssue "seo" "Missing meta description" "high" "Meta descriptions appear below your link in Google. Without one, Google picks random text." "Google your site name. See what text appears under the link. If it is gibberish or missing, meta description is absent." "You lose control over how your site appears in search results."
} else { AddPos "Meta description present" }

# Viewport
$hasViewport = $html -match $patVP
if(-not $hasViewport){
  AddIssue "mobile" "Not mobile responsive" "critical" "Your site lacks a viewport meta tag and will not adapt to phone screens." "Open the site on your phone. Does text overflow? Do you need to pinch-and-zoom?" "Over 60% of searches happen on mobile. You are losing those visitors."
} else { AddPos "Mobile responsive meta tag" }

# H1
$hasH1 = $html -match $patH1
if(-not $hasH1){
  AddIssue "seo" "No H1 heading" "medium" "H1 headings tell Google the main topic of your page." "View page source (Ctrl+U). Search for an H1 tag. If there is none, the page structure is weak." "Missing H1 weakens your search ranking signals."
} else { AddPos "Uses H1 heading" }

# HTTP resources
$httpThings = [regex]::Matches($html, $patHTTP).Count
if($httpThings -gt 0){
  AddIssue "security" "$httpThings HTTP resources (mixed content)" "high" "Assets loading over HTTP on an HTTPS page trigger browser security warnings." "Click the lock icon in the address bar. If it says 'Not Secure' or shows a warning, mixed content is present." "Visitors may get browser warnings and leave your site."
} else { AddPos "No mixed content" }

# Images
$imgCount  = [regex]::Matches($html, $patIMG).Count
$imgAlt    = [regex]::Matches($html, $patAlt).Count
$imgMissing = $imgCount - $imgAlt
if($imgMissing -gt 2){
  AddIssue "a11y" "$imgMissing images missing alt text" "medium" "Alt text helps screen readers and helps Google understand your images." "Right-click an image and inspect. Check if it has an 'alt' attribute." "Blind visitors cannot use your site. Google also gets weaker signals from images."
}
if($imgCount -gt 0){ AddPos "$imgCount images on the page" }

# CSS
$inlineCss = [regex]::Matches($html, $patStyle).Count
$extCss    = [regex]::Matches($html, $patCSS).Count
if($inlineCss -gt 6){
  AddIssue "perf" "$inlineCss inline style blocks" "medium" "Inline style tags cannot be cached. Moving to external CSS speeds up repeat visits." "View page source. Count the style tags. More than 3-4 is unwieldy." "Slower repeat visits, harder code maintenance."
}
if($extCss -gt 6){
  AddIssue "perf" "$extCss external CSS files" "low" "Each CSS file is a separate HTTP request." "Open DevTools Network tab, reload. Count CSS files." "Extra HTTP requests slow down page load."
}
if($extCss -le 6 -and $inlineCss -le 6){ AddPos "Efficient CSS setup" }

# Scripts
$scripts = [regex]::Matches($html, $patScript).Count
if($scripts -gt 25){
  AddIssue "perf" "$scripts external scripts" "high" "$scripts script tags means 3-5+ seconds of load time on standard connections." "Open DevTools Network tab. Filter by JS. Count how many files load." "Slow sites lose ~40% of visitors who expect under 3 second load times."
} elseif($scripts -gt 10){
  AddIssue "perf" "$scripts external scripts" "low" "Consider consolidating or deferring non-critical scripts." "Same check - DevTools Network tab, filter by JS." "Marginal speed improvement possible."
} else {
  $msg = "Light script load ($scripts scripts)"
  AddPos $msg
}

# Forms
$hasForm = $html -match $patForm
if(-not $hasForm){
  AddIssue "ux" "No contact form" "medium" "Without a contact form, visitors need to open their email app and compose from scratch. Some will not bother." "Scroll through the page. Do you see a Name/Email/Message form? If only an email address link, there is no form." "Contact forms typically boost inbound leads by 30-50 percent."
}

# Schema
$hasSchema = $html -match $patSchema
if(-not $hasSchema){
  AddIssue "seo" "No schema markup" "low" "Schema helps Google show your hours, reviews, and events in search results." "Search for your business on Google. Does it show a Knowledge Panel with hours and reviews?" "Detailed search results get higher click-through rates."
}

# Nav
$hasNav = $html -match $patNav
if(-not $hasNav){
  AddIssue "a11y" "No semantic navbar" "low" "A nav tag helps screen readers and search engines find your menu." "Open a screen reader or check page structure with DevTools." "Minor accessibility issue."
}

# Analytics
$hasAnalytics = $html -match $patAnal
if(-not $hasAnalytics){
  AddIssue "business" "No analytics tracking" "medium" "Without analytics, you cannot see how visitors find you or what they do on your site." "Check the page source for references to gtag, analytics.js, or fbq." "You are flying blind - no data on what pages work or where traffic comes from."
} else { AddPos "Analytics active" }

# Page size
if($pageSize -gt 250000){
  $sizeKb = [math]::Round($pageSize/1024,0)
  AddIssue "perf" "Page is ${sizeKb}KB" "medium" "Pages over 250KB load slowly on mobile." "Open DevTools Network tab. Check the Size column for large images or files." "Slow loading increases bounce rate."
} elseif($pageSize -lt 2000){
  $sizeKb = [math]::Round($pageSize/1024,1)
  AddIssue "perf" "Page only ${sizeKb}KB" "high" "Very small page may be broken." "Does the page look complete? If not, content is not loading properly." "Broken page equals lost visitors."
} else {
  $sizeKb = [math]::Round($pageSize/1024,1)
  AddPos "Good page size (${sizeKb}KB)"
}

# ---- PART 2: Visual Analysis ----
if (-not $SkipVisual) {
  Write-Host 'Phase 2: Visual design analysis...' -ForegroundColor Yellow
  $visualResult = & node "$PSScriptRoot\visual-audit.js" $Url 2>&1

  try {
    $vis = $visualResult -join "`n" | ConvertFrom-Json
    if ($vis.issues) {
      foreach ($vIssue in $vis.issues) {
        $vIssues += @{type=$vIssue.type;label=$vIssue.label;severity=$vIssue.severity;detail=$vIssue.detail;check=$vIssue.check;siteHint=$vIssue.siteHint}
      }
    }
    if ($vis.positives) {
      foreach ($vp in $vis.positives) { $vPositives += $vp }
    }
    $vi = $vIssues.Count; $vp = $vPositives.Count; Write-Host "  Found $vi visual issues, $vp positives" -ForegroundColor Green
  } catch {
    Write-Host "  Visual analysis skipped" -ForegroundColor DarkYellow
  }
}

# ---- PART 3: Screenshot ----
$screenshotPath = $null
if (-not $SkipScreenshot) {
  Write-Host 'Phase 3: Taking screenshot...' -ForegroundColor Yellow
  $screenshotPath = Join-Path $OutputDir "${id}-screenshot.png"
  if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

  $ssResult = & node "$PSScriptRoot\screenshot.js" $Url $screenshotPath 2>&1
  if ($LASTEXITCODE -eq 0 -and (Test-Path $screenshotPath)) {
    Write-Host "  Screenshot saved: $screenshotPath" -ForegroundColor Green
    AddPos "Screenshot captured for visual review"
  } else {
    Write-Host "  Screenshot failed" -ForegroundColor DarkYellow
    $screenshotPath = $null
  }
}

# ---- SCORE ----
$score = 100
foreach($iss in $issues){switch($iss.severity){"critical"{$score-=20}"high"{$score-=10}"medium"{$score-=5}"low"{$score-=2}}}
foreach($iss in $vIssues){switch($iss.severity){"critical"{$score-=15}"high"{$score-=8}"medium"{$score-=4}"low"{$score-=2}}}
if($score -lt 0){$score = 0}

$cCount = 0; $hCount = 0; $mCount = 0; $lCount = 0
foreach ($item in $issues) { switch ($item.severity) { 'critical'{$cCount++} 'high'{$hCount++} 'medium'{$mCount++} 'low'{$lCount++} } }
foreach ($item in $vIssues) { switch ($item.severity) { 'critical'{$cCount++} 'high'{$hCount++} 'medium'{$mCount++} 'low'{$lCount++} } }

$allIssues = $issues + $vIssues
$allPositives = $positives + ($vPositives | ForEach-Object { @{detail=$_} })

$cCount = 0; $hCount = 0; $mCount = 0; $lCount = 0
foreach ($item in $allIssues) {
  switch ($item.severity) {
    'critical' { $cCount++ }
    'high'     { $hCount++ }
    'medium'   { $mCount++ }
    'low'      { $lCount++ }
  }
}

# ---- REPORT JSON ----
$reportObj = @{
  id=$id
  businessName=$name
  url=$url
  score=$score
  analyzedAt=(Get-Date -Format "yyyy-MM-dd HH:mm")
  critical=$cCount
  high=$hCount
  medium=$mCount
  low=$lCount
  issues=$allIssues
  positives=$allPositives
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$reportObj | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 (Join-Path $OutputDir "${id}.json")

# ---- EMAIL ----
$e = New-Object System.Collections.Generic.List[string]
$e.Add("Hi there,")
$e.Add("")
$e.Add("I came across the $name website and wanted to share some honest observations. No pitch.")
$e.Add("")
$e.Add("========================================")
$e.Add("Website Health Check - Score: $score/100")
$e.Add("========================================")
$e.Add("")

foreach($iss in ($allIssues|?{$_.severity -eq "critical"})){
  $e.Add("CRITICAL");$e.Add("--------------------")
  $e.Add("- $($iss.label)");$e.Add("  $($iss.detail)");$e.Add("")
}
foreach($iss in ($allIssues|?{$_.severity -eq "high"})){
  $e.Add("HIGH PRIORITY");$e.Add("--------------------")
  $e.Add("- $($iss.label)");$e.Add("  $($iss.detail)");$e.Add("")
}
foreach($iss in ($allIssues|?{$_.severity -eq "medium"})){
  $e.Add("MEDIUM PRIORITY");$e.Add("--------------------")
  $e.Add("- $($iss.label)");$e.Add("  $($iss.detail)");$e.Add("")
}
foreach($iss in ($allIssues|?{$_.severity -eq "low"})){
  $e.Add("LOW PRIORITY");$e.Add("--------------------")
  $e.Add("- $($iss.label)");$e.Add("  $($iss.detail)");$e.Add("")
}
if($allPositives.Count -gt 0){
  $e.Add("WHAT IS WORKING WELL");$e.Add("--------------------")
  foreach($p in $allPositives){
    if ($p.detail) { $e.Add("+ $($p.detail)") }
    else { $e.Add("+ $p") }
  }
  $e.Add("")
}
$e.Add("========================================")
$e.Add("")
$e.Add("Your current website provider should be flagging things like this for you.")
$e.Add("If you ever need a fresh pair of eyes or a new provider, just reach out.")
$e.Add("")
$e.Add("Best,")
$e.Add("David")
$e.Add("DS Studios")

$emailText = $e -join "`r`n"
$emailText | Out-File -Encoding utf8 (Join-Path $OutputDir "${id}-email.txt")

# ---- PROSPECT DATA ----
$prospectData = @{
  businessName = $name
  url = $url
  score = $score
  emailText = $emailText
  issues = $allIssues
}
$prospectData | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 (Join-Path $OutputDir "${id}-prospect.json")

# ---- HTML Report ----
& "$PSScriptRoot\generate-report-html.ps1" -ReportJson (Join-Path $OutputDir "${id}.json") -OutputDir $OutputDir

# ---- SUMMARY ----
Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE" -ForegroundColor Green
Write-Host "  ${name}: ${score}/100" -ForegroundColor White
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Issues:    $($allIssues.Count) total"
Write-Host "  Critical:  $cCount"
Write-Host "  High:      $hCount"
Write-Host "  Medium:    $mCount"
Write-Host "  Low:       $lCount"
Write-Host "  Positives: $($allPositives.Count)"
Write-Host ""
Write-Host "OUTPUT FILES:" -ForegroundColor Cyan
Write-Host "  Report JSON:   $OutputDir/$id.json" -ForegroundColor Green
Write-Host "  HTML Report:   $OutputDir/$id.html" -ForegroundColor Green
Write-Host "  Email draft:   $OutputDir/$id-email.txt" -ForegroundColor Green
Write-Host "  Prospect:      $OutputDir/$id-prospect.json" -ForegroundColor Green
if ($screenshotPath) { Write-Host "  Screenshot:    $screenshotPath" -ForegroundColor Green }
Write-Host ""
Write-Host "To review this prospect:" -ForegroundColor Yellow
Write-Host "  1. Open prospect-review.html in your browser"
Write-Host "  2. Click 'Load' and select ${id}-prospect.json"
Write-Host ""

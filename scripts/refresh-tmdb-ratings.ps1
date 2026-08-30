# ==========================================================================
# ReelPath -- daily TMDB rating refresh
# ==========================================================================
# Every rating-badge that carries a data-tmdb-id (backfilled once by
# scripts/sync-rating-ids.pl -- see that script for which badges are and
# aren't in scope) gets its displayed number re-fetched from TMDB and
# updated in place. vote_average changes over time as more people rate a
# title; this is what keeps every poster/node/rank-item's star rating
# actually current instead of frozen at whatever it was on the day the
# page was built.
#
# One TMDB call per UNIQUE id (not per badge -- the same title can show
# up on several pages), so this stays fast and light even as the badge
# count grows. Only badges whose value actually changed get rewritten,
# to keep the daily commit diff small and readable.
#
# HOW TO RUN:
#   $env:TMDB_TOKEN = '<the TMDB Bearer token>'
#   ./scripts/refresh-tmdb-ratings.ps1
#   Remove-Item Env:\TMDB_TOKEN
# In CI (.github/workflows/rebuild.yml) TMDB_TOKEN comes from the same
# GitHub Actions secret already used by rebuild-coming-soon.ps1.
# ==========================================================================

if (-not $env:TMDB_TOKEN) { Write-Error "TMDB_TOKEN not set."; exit 1 }
$headers = @{ Authorization = "Bearer $($env:TMDB_TOKEN)"; accept = 'application/json' }
$repoRoot = Split-Path -Parent $PSScriptRoot

$files = @("index.html")
$files += Get-ChildItem (Join-Path $repoRoot "watch-order") -Filter *.html | ForEach-Object { "watch-order/$($_.Name)" }
foreach ($sub in @("one-piece","naruto")) {
  $p = Join-Path $repoRoot "watch-order/$sub/filler-list.html"
  if (Test-Path $p) { $files += "watch-order/$sub/filler-list.html" }
}
$files += Get-ChildItem (Join-Path $repoRoot "best") -Filter *.html | Where-Object { $_.Name -ne 'index.html' } | ForEach-Object { "best/$($_.Name)" }
$files += Get-ChildItem (Join-Path $repoRoot "lists") -Filter *.html | Where-Object { $_.Name -ne 'index.html' } | ForEach-Object { "lists/$($_.Name)" }

$badgeRe = [regex]'<span class="rating-badge(?: rating-badge--sm)?" data-tmdb-id="(\d+)" data-media-type="(movie|tv)">([\d.]+)</span>'

# Pass 1: collect every unique (id, mediaType) across all files.
$unique = @{}
foreach ($rel in $files) {
  $path = Join-Path $repoRoot $rel
  if (-not (Test-Path $path)) { continue }
  $html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  foreach ($m in $badgeRe.Matches($html)) {
    $id = $m.Groups[1].Value
    if (-not $unique.ContainsKey($id)) { $unique[$id] = $m.Groups[2].Value }
  }
}
Write-Host "Found $($unique.Count) unique rated titles across $($files.Count) pages."

# Pass 2: fetch fresh vote_average per unique id.
$fresh = @{}
$n = 0
foreach ($id in $unique.Keys) {
  $n++
  $type = $unique[$id]
  $u = "https://api.themoviedb.org/3/$type/$id"
  try {
    $r = Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 15
    if ($null -ne $r.vote_average) {
      $fresh[$id] = [math]::Round([double]$r.vote_average, 1).ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture)
    }
  } catch { Write-Host "  (skip $type/$id -- fetch failed)" }
  if ($n % 75 -eq 0) { Write-Host "  ...$n/$($unique.Count)" }
}

# Pass 3: rewrite only badges whose value actually changed.
$totalChanged = 0
$examples = @()
foreach ($rel in $files) {
  $path = Join-Path $repoRoot $rel
  if (-not (Test-Path $path)) { continue }
  $html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $orig = $html
  $fileChanged = 0
  $html = $badgeRe.Replace($html, {
    param($m)
    $id = $m.Groups[1].Value
    $type = $m.Groups[2].Value
    $old = $m.Groups[3].Value
    if ($fresh.ContainsKey($id) -and $fresh[$id] -ne $old) {
      $script:totalChanged++
      $script:fileChanged++
      if ($script:examples.Count -lt 5) {
        $script:examples += "$rel : id=$id ($type) $old -> $($fresh[$id])"
      }
      return "<span class=`"rating-badge$(if ($m.Value -match 'rating-badge--sm') {' rating-badge--sm'})`" data-tmdb-id=`"$id`" data-media-type=`"$type`">$($fresh[$id])</span>"
    }
    return $m.Value
  })
  if ($html -ne $orig) {
    [System.IO.File]::WriteAllText($path, $html, (New-Object System.Text.UTF8Encoding($false)))
  }
}

Write-Host "`nUpdated $totalChanged badge(s) whose rating changed."
if ($examples.Count -gt 0) {
  Write-Host "Examples:"
  $examples | ForEach-Object { Write-Host "  $_" }
}

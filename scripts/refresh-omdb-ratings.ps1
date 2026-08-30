# ==========================================================================
# ReelPath -- IMDb rating refresh (via OMDb), weekly-cached
# ==========================================================================
# Adds a second, small rating badge (IMDb's own score) right below each
# TMDB rating badge that already carries a data-tmdb-id -- the CSS for
# this was prepped earlier (.rating-badge:nth-of-type(2) in style.css)
# and just needed real data. Reuses the same .rating-badge component, no
# new CSS.
#
# Runs from the SAME daily workflow as the TMDB refresh, but the actual
# OMDb network calls are internally rate-limited to roughly once a week
# per title via scripts/omdb-cache.json (committed to the repo so the
# cache survives between workflow runs): IMDb/RT scores don't move fast
# enough to justify a daily re-fetch, and OMDb's free tier is capped at
# 1,000 requests/day -- with ~300+ titles on the site, a naive daily
# re-fetch of everything would risk that ceiling as more content gets
# added. On any given day this only actually calls OMDb for whichever
# slice of titles haven't been checked in the last 7 days.
#
# Two-step lookup per title, and only the first step ever repeats:
#   1. TMDB /movie/{id}/external_ids or /tv/{id}/external_ids -> imdb_id.
#      Resolved once and cached FOREVER as data-imdb-id="tt..." right on
#      the HTML badge tag itself (or data-imdb-id="none" if TMDB has no
#      IMDb id for that title, so it isn't retried every run).
#   2. OMDb https://www.omdbapi.com/?i={imdb_id}&apikey=... -> imdbRating.
#      This is the part gated to weekly via scripts/omdb-cache.json.
#
# HOW TO RUN:
#   $env:TMDB_TOKEN = '<the TMDB Bearer token>'
#   $env:OMDB_KEY   = '<the OMDb API key>'
#   ./scripts/refresh-omdb-ratings.ps1
#   Remove-Item Env:\TMDB_TOKEN, Env:\OMDB_KEY
# In CI, both come from GitHub Actions secrets -- never hardcoded here.
# ==========================================================================

if (-not $env:TMDB_TOKEN) { Write-Error "TMDB_TOKEN not set."; exit 1 }
if (-not $env:OMDB_KEY) { Write-Error "OMDB_KEY not set."; exit 1 }
$tmdbHeaders = @{ Authorization = "Bearer $($env:TMDB_TOKEN)"; accept = 'application/json' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$cachePath = Join-Path $repoRoot "scripts/omdb-cache.json"

$files = @("index.html")
$files += Get-ChildItem (Join-Path $repoRoot "watch-order") -Filter *.html | ForEach-Object { "watch-order/$($_.Name)" }
foreach ($sub in @("one-piece","naruto")) {
  $p = Join-Path $repoRoot "watch-order/$sub/filler-list.html"
  if (Test-Path $p) { $files += "watch-order/$sub/filler-list.html" }
}
$files += Get-ChildItem (Join-Path $repoRoot "best") -Filter *.html | Where-Object { $_.Name -ne 'index.html' } | ForEach-Object { "best/$($_.Name)" }
$files += Get-ChildItem (Join-Path $repoRoot "lists") -Filter *.html | Where-Object { $_.Name -ne 'index.html' } | ForEach-Object { "lists/$($_.Name)" }

# Matches the primary (TMDB) badge, optionally already carrying a
# resolved (or "none") data-imdb-id from a previous run.
$primaryRe = [regex]'<span class="rating-badge((?: rating-badge--sm)?)" data-tmdb-id="(\d+)" data-media-type="(movie|tv)"(?: data-imdb-id="([^"]*)")?>([\d.]+)</span>'

# ---- Pass 1: collect every unique tmdb id (+ its resolved imdb id, if any) ----
$unique = @{} # tmdbId -> @{ type; imdbId (may be $null / "none" / "tt...") }
foreach ($rel in $files) {
  $path = Join-Path $repoRoot $rel
  if (-not (Test-Path $path)) { continue }
  $html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  foreach ($m in $primaryRe.Matches($html)) {
    $id = $m.Groups[2].Value
    if (-not $unique.ContainsKey($id)) {
      $unique[$id] = [pscustomobject]@{ type = $m.Groups[3].Value; imdbId = $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { $null }) }
    }
  }
}
Write-Host "Found $($unique.Count) unique TMDB-rated titles."

# ---- Pass 2: resolve any still-missing imdb ids via TMDB external_ids ----
$resolvedCount = 0
foreach ($id in @($unique.Keys)) {
  $e = $unique[$id]
  if ($null -ne $e.imdbId) { continue } # already resolved (or known-absent) from a prior run
  $u = "https://api.themoviedb.org/3/$($e.type)/$id/external_ids"
  try {
    $r = Invoke-RestMethod -Uri $u -Headers $tmdbHeaders -Method Get -TimeoutSec 15
    $e.imdbId = if ($r.imdb_id) { $r.imdb_id } else { "none" }
  } catch { $e.imdbId = "none" }
  $resolvedCount++
}
Write-Host "Resolved $resolvedCount new IMDb id(s) via TMDB."

# ---- Load / prune the OMDb rating cache ----
$cache = @{}
if (Test-Path $cachePath) {
  $raw = [System.IO.File]::ReadAllText($cachePath, [System.Text.Encoding]::UTF8)
  if ($raw.Trim()) {
    $obj = $raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $cache[$p.Name] = $p.Value }
  }
}
$today = Get-Date
$staleCutoff = $today.AddDays(-7)

# ---- Pass 3: OMDb fetch, weekly-gated per imdb id ----
$omdbCalls = 0
foreach ($id in $unique.Keys) {
  $imdbId = $unique[$id].imdbId
  if ($imdbId -eq "none") { continue }
  $entry = $cache[$imdbId]
  $isStale = (-not $entry) -or (-not $entry.fetchedAt) -or ([datetime]$entry.fetchedAt -lt $staleCutoff)
  if (-not $isStale) { continue }
  $omdbCalls++
  $u = "https://www.omdbapi.com/?i=$imdbId&apikey=$($env:OMDB_KEY)"
  try {
    $r = Invoke-RestMethod -Uri $u -Method Get -TimeoutSec 15
    $rating = $null
    if ($r.Response -eq "True" -and $r.imdbRating -and $r.imdbRating -ne "N/A") { $rating = $r.imdbRating }
    $cache[$imdbId] = [pscustomobject]@{ rating = $rating; fetchedAt = $today.ToString("yyyy-MM-dd") }
  } catch {
    # Leave any existing cache entry as-is on a transient failure rather
    # than overwriting good data with nothing.
    if (-not $entry) { $cache[$imdbId] = [pscustomobject]@{ rating = $null; fetchedAt = $today.ToString("yyyy-MM-dd") } }
  }
}
Write-Host "Made $omdbCalls OMDb call(s) this run (rest served from cache, <7 days old)."

# Save the cache back as a clean, deterministically-ordered object
# (resolved imdb ids themselves are written straight into the HTML in
# pass 4 below, not stored separately -- this file is only the OMDb
# rating cache).
$ordered = [ordered]@{}
foreach ($k in ($cache.Keys | Sort-Object)) { $ordered[$k] = $cache[$k] }
$cacheJson = $ordered | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($cachePath, $cacheJson, (New-Object System.Text.UTF8Encoding($false)))

# ---- Pass 4: stamp data-imdb-id + sync the secondary IMDb badge ----
# One combined regex matching the primary badge together with any
# secondary IMDb badge ALREADY sitting right after it (from a previous
# run) -- replacing the whole combined match each time is what keeps
# this idempotent. Doing the two pieces as separate passes would just
# re-append a new secondary badge after the old one on every run,
# accumulating duplicates instead of updating in place.
$combinedRe = [regex]('<span class="rating-badge((?: rating-badge--sm)?)" data-tmdb-id="(\d+)" data-media-type="(movie|tv)"(?: data-imdb-id="[^"]*")?>([\d.]+)</span>' + `
  '(?:<span class="rating-badge rating-badge--imdb(?: rating-badge--sm)?" data-tmdb-id="\d+">[\d.]+</span>)?')

foreach ($rel in $files) {
  $path = Join-Path $repoRoot $rel
  if (-not (Test-Path $path)) { continue }
  $html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $orig = $html

  $html = $combinedRe.Replace($html, {
    param($m)
    $sm = $m.Groups[1].Value
    $id = $m.Groups[2].Value
    $type = $m.Groups[3].Value
    $value = $m.Groups[4].Value
    $imdbId = $unique[$id].imdbId
    $primaryTag = "<span class=`"rating-badge$sm`" data-tmdb-id=`"$id`" data-media-type=`"$type`" data-imdb-id=`"$imdbId`">$value</span>"
    $ratingText = $null
    if ($imdbId -and $imdbId -ne "none" -and $cache.ContainsKey($imdbId) -and $cache[$imdbId].rating) {
      $ratingText = $cache[$imdbId].rating
    }
    if ($ratingText) {
      return "$primaryTag<span class=`"rating-badge rating-badge--imdb$sm`" data-tmdb-id=`"$id`">$ratingText</span>"
    }
    return $primaryTag
  })

  if ($html -ne $orig) {
    [System.IO.File]::WriteAllText($path, $html, (New-Object System.Text.UTF8Encoding($false)))
  }
}

Write-Host "Done."

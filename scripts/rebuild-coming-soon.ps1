# ==========================================================================
# ReelPath — "Coming Soon" auto-rebuild
# ==========================================================================
# Regenerates the #upcomingTrack rail on the homepage from TMDB's
# /movie/upcoming endpoint, idempotently -- safe to run on a schedule
# (see .github/workflows/rebuild.yml) with no human curation step.
#
# Design note: earlier passes of this section were hand-picked and
# hand-written (title + a short editorial pitch I was confident about).
# That doesn't scale to an unattended cron job -- an automated run can't
# apply the "only describe what you're sure about" judgment call a
# person/LLM makes by hand. So this script deliberately uses TMDB's own
# `overview` field (trimmed to one clause) as the card's description
# instead of writing new editorial copy. It's TMDB's data, displayed as
# TMDB's data -- nothing fabricated, nothing guessed.
#
# Each card also carries data-release-date="YYYY-MM-DD" so the client-side
# defensive check in main.js (mountComingSoonFilter) can hide anything
# whose release date has already passed, even if this script hasn't run
# since -- see assets/js/main.js.
#
# HOW TO RUN:
#   $env:TMDB_TOKEN = '<the TMDB Bearer token>'
#   ./scripts/rebuild-coming-soon.ps1
#   Remove-Item Env:\TMDB_TOKEN
# In CI (.github/workflows/rebuild.yml) TMDB_TOKEN comes from a GitHub
# Actions secret -- never hardcode it here or anywhere else in the repo.
# ==========================================================================

if (-not $env:TMDB_TOKEN) { Write-Error "TMDB_TOKEN not set. See header comment for usage."; exit 1 }

$headers = @{ Authorization = "Bearer $($env:TMDB_TOKEN)"; accept = 'application/json' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $repoRoot "index.html"

$today = Get-Date
$windowEnd = $today.AddDays(90)

function Trim-Overview($text) {
  if (-not $text) { return "" }
  $t = $text.Trim()
  if ($t.Length -le 140) { return $t }
  $cut = $t.Substring(0, 140)
  $lastSpace = $cut.LastIndexOf(' ')
  if ($lastSpace -gt 80) { $cut = $cut.Substring(0, $lastSpace) }
  return "$cut..."
}

function Html-Escape($s) {
  if (-not $s) { return "" }
  return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

Write-Host "Fetching TMDB /movie/upcoming..."
$u = "https://api.themoviedb.org/3/movie/upcoming?region=US&page=1"
$r = Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 20

# Filter: must have a real near-future release date (TMDB's /upcoming has
# occasionally returned stale re-release entries with old dates -- see
# scripts history) and a poster to show.
$candidates = $r.results | Where-Object {
  $_.poster_path -and $_.release_date -and
  ([datetime]$_.release_date) -ge $today.Date -and
  ([datetime]$_.release_date) -le $windowEnd
} | Sort-Object -Property popularity -Descending | Select-Object -First 10

if ($candidates.Count -eq 0) {
  Write-Host "No qualifying upcoming titles found in the next 90 days -- leaving index.html untouched."
  exit 0
}

Write-Host "Selected $($candidates.Count) titles:"
$cardsHtml = ""
foreach ($m in $candidates) {
  $title = Html-Escape($m.title)
  $desc = Html-Escape(Trim-Overview($m.overview))
  $dateStr = $m.release_date
  $dateLabel = ([datetime]$dateStr).ToString("MMM d, yyyy")
  Write-Host "  $title ($dateStr)"
  $cardsHtml += "          <a class=`"card`" href=`"https://www.themoviedb.org/movie/$($m.id)`" target=`"_blank`" rel=`"noopener`" data-release-date=`"$dateStr`"><img class=`"card-img`" src=`"https://image.tmdb.org/t/p/w500$($m.poster_path)`" alt=`"`" loading=`"lazy`"><span class=`"card-tag`">$dateLabel</span><div class=`"card-plate`"><div><div class=`"card-title`">$title</div><div class=`"card-sub`">$desc</div></div></div></a>`r`n"
}

$html = [System.IO.File]::ReadAllText($indexPath)
# Line-ending-agnostic: match the opening tag itself, then anything up to
# (but not including) the closing </div> that precedes the "next" arrow
# button, regardless of whether the file uses LF or CRLF.
$pattern = '(?s)(<div class="rail-track" id="upcomingTrack">\r?\n)(.*?)(\s*</div>\r?\n\s*</div>\r?\n\s*<button class="scroll-arrow next")'
$match = [regex]::Match($html, $pattern)
if (-not $match.Success) {
  Write-Error "upcomingTrack markers not found -- index.html structure may have changed."
  exit 1
}
$g1 = $match.Groups[1]
$g3 = $match.Groups[3]
$newHtml = $html.Substring(0, $g1.Index + $g1.Length) + $cardsHtml + $html.Substring($g3.Index)
[System.IO.File]::WriteAllText($indexPath, $newHtml, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "index.html Coming Soon rail rebuilt."

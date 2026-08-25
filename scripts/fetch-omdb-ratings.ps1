# ==========================================================================
# ReelPath — OMDb ratings fetch (IMDb + Rotten Tomatoes)
# ==========================================================================
# STATUS: prepared, NOT yet run. No OMDb API key exists yet — this script
# is ready to go the moment one does. Do not commit a key into this file
# or into any tracked file; it is read from a process-local environment
# variable only, exactly like the TMDB scripts before it (see
# assets/js/main.js history / commit log for that pattern).
#
# What this does, in order:
#   1. For every title already on the site (the same list TMDB was queried
#      for — trending rail, watch-order nodes, genre picks, list entries),
#      call TMDB's /movie/{id}/external_ids or /tv/{id}/external_ids to
#      get the imdb_id. This step needs a TMDB token (same one already
#      used elsewhere) — not the OMDb key.
#   2. For each imdb_id, call OMDb: https://www.omdbapi.com/?i={imdb_id}&apikey={KEY}
#   3. Pull imdbRating from the response, and scan the Ratings[] array for
#      a Source == "Rotten Tomatoes" entry -- not every title has one, so
#      missing RT data is expected and handled by simply omitting that
#      badge for that title (same graceful-fallback rule used everywhere
#      else on this site: no data in, no badge out, never a broken image
#      or a guessed number).
#   4. Write everything to a local JSON file for review (never straight to
#      HTML) so the results can be spot-checked before anything gets
#      written into the site, same as every other content pass here.
#   5. A SEPARATE follow-up pass (not in this file) injects the extra
#      badge(s) next to the existing TMDB rating-badge on each poster
#      card, reusing the same .rating-badge CSS component with a second
#      badge appended rather than a new component.
#
# HOW TO RUN ONCE A KEY EXISTS:
#   $env:TMDB_TOKEN  = '<the existing TMDB Bearer token>'
#   $env:OMDB_APIKEY = '<the new OMDb key>'
#   ./scripts/fetch-omdb-ratings.ps1
#   Remove-Item Env:\TMDB_TOKEN, Env:\OMDB_APIKEY
#
# Output: omdb-ratings.json in the current directory (gitignored — this is
# a working file for the injection pass, not a site asset).
# ==========================================================================

if (-not $env:TMDB_TOKEN) { Write-Error "TMDB_TOKEN not set. See header comment for usage."; exit 1 }
if (-not $env:OMDB_APIKEY) { Write-Error "OMDB_APIKEY not set. See header comment for usage."; exit 1 }

$tmdbHeaders = @{ Authorization = "Bearer $($env:TMDB_TOKEN)"; accept = 'application/json' }

# The full title roster this site currently has poster/rating cards for.
# [tmdbId, type] pairs -- tmdbId values come from the site's existing
# TMDB fetch history (tmdb-ratings-full.json from the ratings pass).
# Fill this array from that file before running; left as an illustrative
# sample here so the script is syntactically complete and ready to extend.
$titles = @(
  @{ tmdbId = 1726;  type = 'movie' }  # Iron Man (sample -- replace/extend with the full roster)
)

function Get-ExternalIds($tmdbId, $type) {
  $u = "https://api.themoviedb.org/3/$type/$tmdbId/external_ids"
  try { Invoke-RestMethod -Uri $u -Headers $tmdbHeaders -Method Get -TimeoutSec 15 } catch { $null }
}

function Get-Omdb($imdbId) {
  $u = "https://www.omdbapi.com/?i=$imdbId&apikey=$($env:OMDB_APIKEY)"
  try { Invoke-RestMethod -Uri $u -Method Get -TimeoutSec 15 } catch { $null }
}

$results = [ordered]@{}
foreach ($t in $titles) {
  $ext = Get-ExternalIds $t.tmdbId $t.type
  $imdbId = $ext.imdb_id
  if (-not $imdbId) { Write-Host "$($t.tmdbId): no imdb_id, skipping"; continue }

  $omdb = Get-Omdb $imdbId
  if (-not $omdb -or $omdb.Response -eq 'False') { Write-Host "$imdbId: OMDb lookup failed"; continue }

  $rt = $null
  if ($omdb.Ratings) {
    foreach ($r in $omdb.Ratings) {
      if ($r.Source -eq 'Rotten Tomatoes') { $rt = $r.Value; break }
    }
  }

  $results["$($t.tmdbId)"] = [ordered]@{
    imdbId = $imdbId
    imdbRating = $omdb.imdbRating   # e.g. "8.4" or "N/A"
    rottenTomatoes = $rt            # e.g. "94%" or $null if not listed
  }
  Write-Host "$($t.tmdbId) / $imdbId : IMDb=$($omdb.imdbRating) RT=$rt"
  Start-Sleep -Milliseconds 200   # OMDb free tier is rate-limited; be polite
}

$json = $results | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText("omdb-ratings.json", $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Written to omdb-ratings.json -- review before running the injection pass."

# ==========================================================================
# ReelPath — homepage "Coming soon" / "Trending this week" data refresh
# ==========================================================================
# Pulls TMDB's /movie/upcoming and /trending/all/week endpoints at build
# time (never client-side) and writes the raw results to a local JSON file
# for review. A SEPARATE manual pass reads that JSON and updates the two
# rails in index.html (#upcomingTrack / #trendingWeekTrack) -- this script
# only fetches and reviews, it never writes HTML directly, same as every
# other content pass on this site.
#
# HOW TO RUN:
#   $env:TMDB_TOKEN = '<the existing TMDB Bearer token>'
#   ./scripts/fetch-homepage-sections.ps1
#   Remove-Item Env:\TMDB_TOKEN
#
# Output: homepage-sections.json in the current directory (gitignored --
# scripts/*.json is already excluded via .gitignore).
#
# After reviewing the output:
#   1. Filter out any result with a release/air date far from "today" --
#      TMDB's /movie/upcoming has occasionally returned old re-release
#      dates (classics doing a limited theatrical re-run); only keep
#      entries within roughly the next 60-90 days.
#   2. Check each upcoming/trending title's name against the current
#      franchise-guide roster (watch-order/*.html) -- MCU, Star Wars,
#      X-Men, Fast & Furious, One Piece, Naruto, Demon Slayer, Fate, Wan
#      Universe, and whatever's been added since. Any match gets a direct
#      link to that guide instead of an outbound TMDB link.
#   3. Only include titles you can write an accurate, non-fabricated
#      one-line description for -- same rule as every other content pass.
# ==========================================================================

if (-not $env:TMDB_TOKEN) { Write-Error "TMDB_TOKEN not set. See header comment for usage."; exit 1 }
$headers = @{ Authorization = "Bearer $($env:TMDB_TOKEN)"; accept = 'application/json' }

$upcoming = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/movie/upcoming?region=US&page=1" -Headers $headers
$trending = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/trending/all/week" -Headers $headers

$results = [ordered]@{}
$upList = @()
foreach ($m in ($upcoming.results | Select-Object -First 16)) {
  $upList += [ordered]@{ title=$m.title; id=$m.id; releaseDate=$m.release_date; rating=[math]::Round($m.vote_average,1); votes=$m.vote_count; poster=$m.poster_path; overview=$m.overview }
}
$results['upcoming'] = $upList

$trList = @()
foreach ($m in ($trending.results | Select-Object -First 16)) {
  $name = if ($m.media_type -eq 'tv') { $m.name } else { $m.title }
  $date = if ($m.media_type -eq 'tv') { $m.first_air_date } else { $m.release_date }
  $trList += [ordered]@{ title=$name; id=$m.id; mediaType=$m.media_type; releaseDate=$date; rating=[math]::Round($m.vote_average,1); votes=$m.vote_count; poster=$m.poster_path; overview=$m.overview }
}
$results['trending'] = $trList

$json = $results | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText("homepage-sections.json", $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Upcoming: $($upList.Count), Trending: $($trList.Count) -- written to homepage-sections.json, review before editing index.html."

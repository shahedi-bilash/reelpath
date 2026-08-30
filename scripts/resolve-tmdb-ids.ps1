# ==========================================================================
# ReelPath -- resolve TMDB IDs for the rating-badge manifest
# ==========================================================================
# Reads scripts/_rating-manifest.json (from `perl scripts/sync-rating-ids.pl
# --extract`), looks up each unique (title, poster) pair against TMDB, and
# writes scripts/_rating-resolved.json mapping "title|poster" -> {id,
# mediaType}. A match is only accepted when a search result's own
# poster_path is byte-identical to the poster already on the page --
# that poster was already trusted (it's live on the site), so this turns
# "which TMDB entry is this" into a verified lookup instead of a guess.
# No exact match => left unresolved, never a best-effort guess.
#
# HOW TO RUN:
#   $env:TMDB_TOKEN = '<the TMDB Bearer token>'
#   ./scripts/resolve-tmdb-ids.ps1
#   Remove-Item Env:\TMDB_TOKEN
# ==========================================================================

if (-not $env:TMDB_TOKEN) { Write-Error "TMDB_TOKEN not set."; exit 1 }
$headers = @{ Authorization = "Bearer $($env:TMDB_TOKEN)"; accept = 'application/json' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot "scripts/_rating-manifest.json"
$outPath = Join-Path $repoRoot "scripts/_rating-resolved.json"

# Explicit UTF8 read -- Get-Content's default encoding on Windows
# PowerShell 5.1 is NOT UTF-8, and misreading the manifest's UTF-8 bytes
# (titles like "Chainsaw Man -- The Movie" with an em dash, "Fate/kaleid
# liner Prisma[star]Illya") reproduces the exact double-encoding
# corruption this project has hit before from the Perl side -- same
# symptom, different cause (a wrong read encoding here, not mixed
# UTF8-flagged/raw strings). Read as raw bytes and decode explicitly so
# there's no ambiguity.
$manifestBytes = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$manifest = $manifestBytes | ConvertFrom-Json
$unique = @{}
foreach ($e in $manifest.entries) {
  $key = "$($e.title)|$($e.poster)"
  if (-not $unique.ContainsKey($key)) {
    $unique[$key] = [pscustomobject]@{ title = $e.title; poster = $e.poster; hint = $e.hint }
  }
}
Write-Host "Resolving $($unique.Count) unique titles (from $($manifest.entries.Count) badges)..."

function Try-Search($title, $type) {
  $u = "https://api.themoviedb.org/3/search/$type`?query=" + [uri]::EscapeDataString($title) + "&include_adult=false&language=en-US&page=1"
  try {
    $r = Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 15
    return $r.results
  } catch { return @() }
}

$resolved = [ordered]@{}
$n = 0; $ok = 0; $miss = 0
foreach ($key in $unique.Keys) {
  $n++
  $e = $unique[$key]
  $types = if ($e.hint -eq 'tv') { @('tv','movie') } elseif ($e.hint -eq 'movie') { @('movie','tv') } else { @('movie','tv') }
  $found = $null
  foreach ($type in $types) {
    $results = Try-Search $e.title $type
    $match = $results | Where-Object { $_.poster_path -eq $e.poster } | Select-Object -First 1
    if ($match) { $found = [pscustomobject]@{ id = $match.id; mediaType = $type }; break }
  }
  if ($found) {
    $resolved[$key] = $found
    $ok++
  } else {
    $resolved[$key] = $null
    $miss++
  }
  if ($n % 50 -eq 0) { Write-Host "  ...$n/$($unique.Count) ($ok matched, $miss unresolved so far)" }
}

Write-Host "Done: $ok matched, $miss unresolved out of $($unique.Count) unique titles."
$json = $resolved | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outPath"

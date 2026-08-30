// ==========================================================================
// ReelPath -- live search proxy (Cloudflare Pages Function)
// ==========================================================================
// GET /search?q=<query>
//
// The static assets/search-index.json only ever covers what's already
// been curated on this site -- it can never answer "any movie", because
// that requires TMDB's actual database. This function is the fix: it
// proxies the query to TMDB's /search/multi endpoint server-side, so the
// TMDB token stays in a Cloudflare Pages environment variable and never
// reaches the browser.
//
// REQUIRED SETUP (one-time, per Cloudflare Pages project):
//   Cloudflare dashboard -> Pages project -> Settings -> Environment
//   variables -> add TMDB_TOKEN (Production, and Preview if you want
//   branch previews to search too). This is separate from the TMDB_TOKEN
//   GitHub Actions secret used by .github/workflows/rebuild.yml --
//   Cloudflare does not read GitHub secrets, both have to be set.
//
// Response shape: { results: [{ id, mediaType, title, year, rating,
// poster, tmdbUrl }] }. The frontend (mountSiteSearch in assets/js/
// main.js) cross-references each title against the local curated index
// to decide whether to badge it "Watch Order Guide" / "In our Best Of
// list" / "In our Lists", or show it plainly as a TMDB-only result.
// ==========================================================================

export async function onRequestGet(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  const q = (url.searchParams.get("q") || "").trim();

  if (!q) return json({ results: [] }, 200);

  if (!env.TMDB_TOKEN) {
    // Fails loudly and specifically so a missing Cloudflare env var is
    // obvious from the response rather than looking like a silent bug.
    return json({ results: [], error: "search not configured (missing TMDB_TOKEN)" }, 500);
  }

  const tmdbUrl =
    "https://api.themoviedb.org/3/search/multi?query=" +
    encodeURIComponent(q) +
    "&include_adult=false&language=en-US&page=1";

  let tmdbRes;
  try {
    tmdbRes = await fetch(tmdbUrl, {
      headers: {
        Authorization: "Bearer " + env.TMDB_TOKEN,
        accept: "application/json",
      },
    });
  } catch (e) {
    return json({ results: [], error: "upstream fetch failed" }, 502);
  }

  if (!tmdbRes.ok) {
    return json({ results: [], error: "upstream status " + tmdbRes.status }, 502);
  }

  let data;
  try {
    data = await tmdbRes.json();
  } catch (e) {
    return json({ results: [], error: "upstream returned invalid JSON" }, 502);
  }

  const results = (data.results || [])
    .filter((r) => r.media_type === "movie" || r.media_type === "tv")
    .slice(0, 10)
    .map((r) => {
      const title = r.title || r.name || "";
      const dateStr = r.release_date || r.first_air_date || "";
      return {
        id: r.id,
        mediaType: r.media_type,
        title: title,
        year: dateStr ? dateStr.slice(0, 4) : "",
        rating: typeof r.vote_average === "number" ? Math.round(r.vote_average * 10) / 10 : null,
        poster: r.poster_path ? "https://image.tmdb.org/t/p/w200" + r.poster_path : null,
        tmdbUrl: "https://www.themoviedb.org/" + r.media_type + "/" + r.id,
      };
    })
    .filter((r) => r.title);

  // Short edge/browser cache -- popular queries (a franchise name, a big
  // release) get typed by many visitors; TMDB's own data doesn't change
  // fast enough to need a fresh call every time.
  return json({ results }, 200, "public, max-age=300");
}

function json(body, status, cacheControl) {
  const headers = { "content-type": "application/json; charset=utf-8" };
  if (cacheControl) headers["cache-control"] = cacheControl;
  return new Response(JSON.stringify(body), { status, headers });
}

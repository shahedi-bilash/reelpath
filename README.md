# ReelPath — Claude Code Build Brief

**সংক্ষেপে:** ReelPath হলো Shahedi Bilash-এর personal, zero-cost side-project — একটা "before you press play" platform যেখানে (১) anime/comic/franchise movies-series-এর জন্য interactive **watch-order guide** থাকবে (কোন episode/movie কোন order-এ দেখতে হবে, filler skip করা যাবে), এবং (২) genre অনুযায়ী **curated "best of" recommendation list** থাকবে। Zero budget, organic SEO/virality-নির্ভর growth, Cloudflare Pages-এ free host হবে — ঠিক যেভাবে তার আগের project **The Bangladesh Trip** (https://the-bangladesh-trip.pages.dev/) বানানো হয়েছে, একই zero-cost static-site model।

এই ব্র্যান্ড-নাম **এখনো placeholder**: "ReelPath". চাইলে বদলে দেওয়া যাবে, কোড জুড়ে সব জায়গায় এই নামটাই বসানো আছে বলে rename simple find-replace-এই হয়ে যাবে।

---

## 1. Design system — attached prototype-ই source of truth

সাথে **`reelpath-prototype.html`** attach করা আছে — এটাই canonical design reference। এখানে যা যা আগে থেকেই কাজ করছে (এই HTML/CSS/JS-এর structure আর logic হুবহু পুরো site জুড়ে reuse করতে হবে):

- **Color tokens** (CSS `:root` variables): near-black navy background (`--bg:#05060a`), elevated card surfaces (`--bg-elev`, `--bg-elev-2`), single accent color electric violet (`--gold:#7c6cf5` — variable-নাম এখনো "gold" রয়ে গেছে legacy কারণে, কিন্তু value violet; চাইলে rename করে দিও), dim/muted variant (`--gold-dim:#4f43b8`), text colors (`--text`, `--text-dim`, `--text-faint`).
- **Typography:** display headings = Google Font "Bebas Neue" (poster-style, uppercase), body/UI = "Inter".
- **Signature interactive component — "Watch-Order Path":** horizontal node-and-line timeline (`.path-track`, `.path-nodes`, `.node`), gold/violet glowing connector line, with a toggle (`#fillerToggle`) that hides/shows filler-episode nodes live. **এই exact pattern প্রতিটা franchise page-এ reuse করতে হবে** — এটাই সাইটের সবচেয়ে defensible/shareable feature।
- **Trending rail:** auto-playing horizontal marquee (`.rail`, `.rail-track`, `@keyframes marquee`), pauses on hover, content duplicated for seamless loop.
- **3D tilt + parallax:** poster cards tilt on mousemove (`perspective()/rotateX/rotateY`), hero has a scroll-based parallax glow + grain layer. Keep this subtle-tier — no heavy Three.js.
- **Scroll-reveal:** `IntersectionObserver`-based fade+slide-in on section headers, cards, steps (`.reveal` / `.reveal.in` classes).
- **Genre cards:** currently have a self-generated abstract "atmosphere glow" JPEG per genre (embedded as base64 in the prototype, purely because the chat-preview sandbox couldn't load external images — **on real hosting this constraint doesn't exist**, so replace these with real photography/poster art, see §3).
- **Logo:** the uploaded reel-icon logo (violet film-reel mark) — attached separately as `logo.png` (full-resolution, transparent background) and the favicon set (`favicon.ico`, `favicon-32.png`, `favicon-180.png`). Use these as real files in the project (e.g. `/assets/logo.png`, `/favicon.ico`) — **do not** re-embed as base64 on the live site; base64 was only a workaround for the chat-preview sandbox.
- **Footer copyright line (exact, keep as-is):** `© 2026 · Shahedi Bilash · REELPATH` — "Shahedi Bilash" is a `mailto:shahedibilash2@gmail.com` link. Affiliate-disclosure sentence stays above it (matches The Bangladesh Trip's honest-disclosure tone).
- Reduced-motion (`prefers-reduced-motion`) already disables all animation/transition — keep this accessibility behavior everywhere.

**Note on the atmosphere JPEGs in the prototype:** those 8 genre-card background images and the hero background are procedurally generated abstract gradients (my own code, not real photos, not copyrighted) — they're actually fine to ship as-is on day one if real imagery isn't ready yet, but they're a placeholder mood, not final content.

---

## 2. Site structure — multi-page (SEO is the whole point)

Static HTML, no build tools, no framework — same approach as The Bangladesh Trip. Multi-page is mandatory here, not optional: "MCU watch order" and "best Korean crime dramas" are different Google searches and need their own indexable URL to ever rank.

```
/                              → homepage (= the prototype, extended)
/watch-order/                  → hub: grid/list of all franchise guides
/watch-order/one-piece.html    → individual franchise guide (flagship — has the filler-skip demo)
/watch-order/mcu.html
/watch-order/fate.html
/watch-order/wan-universe.html
/best/                         → hub: grid of all genre pages
/best/action-movies.html
/best/thriller-movies.html
/best/horror-movies.html
/best/sci-fi-movies.html
/best/anime.html
/best/romance-movies.html
/best/crime-dramas.html
/best/comedy-movies.html
/about.html                    → who runs this, disclosure, credits
```

Each `/watch-order/<franchise>.html` page reuses the Watch-Order Path component from the prototype, populated with that franchise's real episode/movie data. Each `/best/<genre>.html` page is a ranked list (poster + title + one-line pitch + "where to watch" button) — no watch-order needed there, just ranking.

Standard SEO hygiene for every page: unique `<title>`, meta description, one `<h1>`, semantic headings, internal links between related franchise/genre pages, and a shared `sitemap.xml` + `robots.txt` at the root (mirror how The Bangladesh Trip is set up — check that project's repo for the exact pattern already in use).

---

## 3. Real images — TMDB API (free, legal, required before real launch)

**Do not hotlink or reproduce actual movie/anime poster art from Google Images, Pinterest, or fan sites — that's copyrighted.** The correct, legal, standard-practice route for a movie database site is **The Movie Database (TMDB) API**:

1. Create a free account at themoviedb.org → Settings → API → request a free "Developer" API key (instant approval, no cost).
2. Use the `/search/movie`, `/search/tv`, or `/find` endpoints to get poster/backdrop paths.
3. Poster URLs are built as `https://image.tmdb.org/t/p/w500/{poster_path}` — no image hosting needed on our end at all, TMDB serves the images directly, still zero-cost.
4. **Attribution is required** by TMDB's terms — add a small credit line in the footer: "This product uses the TMDB API but is not endorsed or certified by TMDB." (standard, non-negotiable wording per their API terms — check themoviedb.org/documentation/api/terms-of-use for the current exact required phrasing before shipping).
5. Store the API key as a build-time/config value, not hardcoded in a public repo if this ever goes further than static fetch-at-build — for a pure static site with no backend, calling TMDB client-side with the key exposed in JS is technically how many hobby projects do it (TMDB's free tier allows this), but flag this trade-off to the user before finalizing.

Until TMDB is wired in, the prototype's generated atmosphere JPEGs are an acceptable placeholder — swap them out page by page as content gets built.

---

## 4. MVP content scope (what to launch with)

Per the earlier plan, this launches as a fuller MVP rather than a tiny single-franchise test:

**Watch-order franchises (start with 4):**
- One Piece (flagship — skip-filler is the hero feature)
- Marvel Cinematic Universe (release order vs. chronological toggle — same node/path pattern, different toggle logic)
- Fate Series (notoriously confusing — good SEO angle)
- The Conjuring / Wan Universe (proves the "non-anime franchise" half of the concept)

**Genre pages (start with all 8 shown in the prototype):** Action, Thriller, Horror, Sci-Fi, Anime, Romance, Crime, Comedy — each with a ranked top-10-ish list to start; can grow over time.

---

## 5. Affiliate monetization (slot exists, logic comes later)

The prototype already has a "Where to watch" button pattern implied in the card layout and a disclosure line in the footer. For this build pass: **wire the UI slot, leave the actual affiliate link targets as TODO/placeholder** — Bilash will provide the actual affiliate program links (JustWatch-style streaming deep-links where available, or Amazon Associates for physical media/merch as a fallback since native BD streaming affiliate programs are limited) in a follow-up pass once accounts are set up.

---

## 6. Deployment

Same as The Bangladesh Trip: static site → Cloudflare Pages, free tier, custom domain optional later (~$10/yr when ready, not required for launch). Push to a personal GitHub repo first (version control), connect that repo to Cloudflare Pages for auto-deploy on push.

---

## 7. What to do first (suggested build order)

1. Scaffold the folder structure above; copy the prototype's `<head>`/design-tokens/fonts into a shared partial or just duplicate consistently across pages (no build tooling, so literal duplication is fine at this scale).
2. Swap the base64 logo/favicon for the real attached files.
3. Build the One Piece watch-order page fully (real episode data, real filler list) — this is the flagship proof.
4. Build the `/watch-order/` and `/best/` hub pages (simple grids linking out).
5. Build 3-4 genre pages with real curated picks.
6. Wire TMDB for real poster art site-wide, replacing the placeholder atmosphere JPEGs.
7. Add `sitemap.xml`, `robots.txt`, meta tags per page.
8. Deploy to Cloudflare Pages, test on mobile.
9. Come back for affiliate link wiring once accounts are ready.

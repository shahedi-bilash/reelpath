# ReelPath watch-order data

Raw, machine-readable watch-order data for every franchise guide on
[ReelPath](https://reelpath.pages.dev) — the same data that powers the
interactive paths on the site itself, published here so anyone can use it,
check it, or fix it.

## Files

One JSON file per franchise, matching its guide's URL slug:

| File | Guide |
|---|---|
| `one-piece.json` | [One Piece](https://reelpath.pages.dev/watch-order/one-piece.html) |
| `mcu.json` | [Marvel Cinematic Universe](https://reelpath.pages.dev/watch-order/mcu.html) |
| `naruto.json` | [Naruto](https://reelpath.pages.dev/watch-order/naruto.html) |
| `demon-slayer.json` | [Demon Slayer](https://reelpath.pages.dev/watch-order/demon-slayer.html) |
| `star-wars.json` | [Star Wars](https://reelpath.pages.dev/watch-order/star-wars.html) |
| `x-men.json` | [X-Men](https://reelpath.pages.dev/watch-order/x-men.html) |
| `fast-furious.json` | [Fast & Furious](https://reelpath.pages.dev/watch-order/fast-furious.html) |
| `attack-on-titan.json` | [Attack on Titan](https://reelpath.pages.dev/watch-order/attack-on-titan.html) |
| `harry-potter.json` | [Harry Potter](https://reelpath.pages.dev/watch-order/harry-potter.html) |
| `fate.json` | [Fate Series](https://reelpath.pages.dev/watch-order/fate.html) |
| `wan-universe.json` | [The Conjuring / Wan Universe](https://reelpath.pages.dev/watch-order/wan-universe.html) |

## Schema

```jsonc
{
  "franchise": "One Piece",           // display name
  "slug": "one-piece",                // matches the guide's URL and filename
  "guideUrl": "https://...",          // the full interactive guide
  "source": "ReelPath (...)",
  "license": "CC-BY-4.0 -- attribution appreciated, corrections and additions welcome via PR",
  "entryCount": 20,
  "entries": [
    {
      "position": 1,                  // release/reading order, 1-indexed
      "title": "East Blue",
      "poster": "https://image.tmdb.org/...",   // omitted if none exists
      "meta": "Ep 1–61",              // whatever the guide shows under the title
      "filler": false,                // true = anime-only, safe to skip
      "sideStory": true,              // present + true only on optional side entries (Fate)
      "type": "movie",                // present only on franchises that mix movies + series (MCU, Star Wars)
      "chronoPosition": 3,            // present only on franchises with a chronological order (MCU, Star Wars, Wan Universe, Fast & Furious, X-Men)
      "rating": 8.8                   // TMDB vote_average at time of writing; omitted where a shared show-level rating would be misleading (e.g. arc-level anime nodes)
    }
  ]
}
```

Not every field appears on every entry — `poster`, `rating`, `sideStory`,
`type` and `chronoPosition` are all conditional on what that particular
entry and franchise actually have.

## Using this data

Anything you want — build your own visualization, feed it into a personal
tool, remix it. Attribution back to ReelPath is appreciated but this is
meant to be genuinely useful data, not a locked-down asset.

## Something wrong or missing?

These files are generated from the same source as the live guides, so if
you spot an error here, it's an error on the site too — please open a PR
against this repo (or an issue if you're not sure how to fix it) rather
than just the JSON. Ratings drift over time as TMDB's vote counts change;
episode ranges for ongoing anime (One Piece, and eventually others) will
need periodic bumps as new arcs air.

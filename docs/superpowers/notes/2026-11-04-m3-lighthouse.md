# M3 Task 7: Lighthouse on the player and public pages (2026-11-04)

Run: `LIGHTHOUSE_BASE=http://localhost:3001 bin/rails grindin:lighthouse` (Lighthouse 13.6.0, `--preset=perf`,
mobile form factor and screen emulation, Chrome headless, simulated slow 4G). The task fails below 90 on
performance or accessibility. Server: development (`bin/rails server`, Puma, uncompressed assets), demo
event `demo-open`, profile of `demo-p0@grindin.test` (`/p/player-1`).

Port 3001 rather than the usual dev server on 3000: that server was booted before `app/queries/` existed,
so `/p/:handle` answered 500 there (`uninitialized constant ProfilesController::Profiles`); a fresh boot
serves it. Restarting the 3000 server fixes it; nothing in the code.

## Scores (performance / accessibility / best practices)

| Page | Perf | A11y | Best practices |
| --- | ---: | ---: | ---: |
| `/t/demo-open` | 95 | 100 | 100 |
| `/t/demo-open/standings` | 92 | 100 | 100 |
| `/t/demo-open/pairings` | 95 | 100 | 100 |
| `/p/player-1` | 95 | 100 | 100 |

Performance varies by about ±3 between runs (an earlier run, before dropping the empty `application.css`:
94 / 95 / 95 / 93). All four are at or above 90.

## What changed for these pages

- Icons: local SVG sprite (`app/assets/images/icons.svg`, 40 Phosphor light symbols) through `icon(name)`;
  the Phosphor icon font CSS from cdn.jsdelivr is gone (it was only in the organizer layout, so icons in
  the play/public layouts were not drawn at all before).
- JavaScript: Flowbite and Leaflet are vendored (`vendor/javascript`); Flowbite is imported only by the
  `organizer` entry point (application layout), Leaflet only when a map controller connects (dynamic
  import, `preload: false`). Before, every page loaded `flowbite.turbo.min.js` and Leaflet from
  cdn.jsdelivr (the map controller is eager-loaded and imported Leaflet statically).
- Fonts: Google Fonts CSS loads non-blocking (`media="print"` swapped on load, `<noscript>` fallback,
  `display=swap`) in the play, public and timer layouts.
- The empty Propshaft `application.css` (a comment-only manifest) is no longer linked from the play and
  public layouts: it was a render-blocking request of 893 bytes costing ~880 ms on simulated 4G.
- `theme-color`, `description` (per page with `content_for(:description)`, default per layout), nav
  `aria-label`, `<main>` in every page layout, sized avatar image on the profile.

## Remaining opportunities (all four pages)

- Render-blocking requests (600–1,150 ms est.): `tailwind.css`, 81 KB uncompressed from the dev server
  (14 KB gzipped). In production the response is compressed (Thruster), which removes most of it;
  inlining critical CSS is not worth it at that size.
- Reduce unused JavaScript (125 KiB est.): `turbo.min.js` (91 KiB unused of 106) and `stimulus.min.js`
  (37 of 46), uncompressed in dev. Both are the app's runtime; out of our hands short of dropping Turbo.
- Minify JavaScript (2 KiB): our own Stimulus controllers, served as written by importmap (no bundler).
- Document request latency (4–32 KiB): the HTML is not compressed by the dev server.
- First Contentful Paint 2.4–2.7 s on the simulated slow 4G link, driven by the CSS above.
- Forced reflow / network dependency tree: informational; the chain is HTML → CSS + importmap modules.

## Re-run after M4b + live standings (2026-11-04, main 18b03ce)

Same method (dev server on 3000, Lighthouse via `bin/rails grindin:lighthouse`). The public pairings and
standings pages now open an Action Cable subscription; scores held.

| Page | Perf | A11y | Best practices |
| --- | ---: | ---: | ---: |
| `/t/demo-open` | 95 | 100 | 100 |
| `/t/demo-open/standings` | 95 | 100 | 100 |
| `/t/demo-open/pairings` | 95 | 100 | 100 |
| `/p/player-1` | 93 | 100 | 100 |

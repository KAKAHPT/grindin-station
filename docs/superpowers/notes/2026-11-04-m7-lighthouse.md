# M7: Lighthouse on the redesigned public pages (2026-11-04)

Run: `bin/rails "grindin:lighthouse[http://localhost:3000/...]"` (Lighthouse 13.6.0, `--preset=perf`, mobile form
factor and screen emulation, Chrome headless, simulated slow 4G). The task fails below 90 on performance or
accessibility. Server: development (`bin/dev` on :3000, Puma, uncompressed assets), demo event `demo-cup`
(15 players, swiss round 2), branch `m7-design` after the Task 7 sweep.

## Scores (performance / accessibility / best practices)

| Page | Perf | A11y | Best practices |
| --- | ---: | ---: | ---: |
| `/` (landing) | 93 | 100 | 100 |
| `/t/demo-cup` | 95 | 100 | 100 |
| `/t/demo-cup/standings` | 94 | 100 | 100 |
| `/t/demo-cup/pairings` | 95 | 98 | 100 |

All four are at or above 90. Performance varies by about ±3 between runs.

## Not in the target set

| Page | Perf | A11y | Best practices |
| --- | ---: | ---: | ---: |
| `/events` (before removing Leaflet) | 83 | 98 | 100 |
| `/events` (after, three runs) | 83 / 79 / 83 | 98 | 100 |

Leaflet was dead code (no view uses the map controller any more) and is gone: the jsdelivr stylesheet in the
`application` layout, `map_controller.js`, the importmap pin, `vendor/javascript/leaflet.js` and the jsdelivr host in
the CSP `style-src`. The score did not move: what remains is the organizer entry point (Flowbite, about 219 KiB of
unused JavaScript on a public list), the render-blocking Google Fonts and the two stylesheets of the `application`
layout. `/events`, `/tournaments`, `/leagues` and `/circuits` keep that layout for the modal Sign in (the
authentication system tests open it from `/events`); moving them to `public` with a plain Sign in link would drop
Flowbite from them.

## Inventory

`inventory-m7-desktop.png` and `inventory-m7-mobile.png` (this folder): 34 pages each, desktop 1440 px and phone
390 px, as a visitor, as the player `demo-p3@grindin.test` and as the organizer `demo-org@grindin.test` (landing,
events and past events, tournaments, leagues, Rankings and a circuit, sign in/up, forgot/reset password,
`/t/demo-cup` event/pairings/standings/me, `/t/demo-big` pairings, account, notifications, public profile, and the
organizer's tournaments, overview, roster, rounds, Judge Center, staff, settings, new tournament, circuits, a
circuit, leagues). Every shot answered 200, no element carries a `purple`/`orange-700`/`dark:`/`gray-` class, none
scrolls sideways and none shows a missing translation. The single shots and the scripts (`inventory-m7.js`,
`sheets-m7.js`) are in `.superpowers/sdd/2026-11-04-grindin-station-m7-design/shots/inventory/`.

Landing art: c6, c17 and c44 are one image, as are c2 and c23. `public/mock/art/` holds the same 48 crops with the
same duplicates (and only logo PNGs besides), so there is no unused distinct crop to swap in; left as is.

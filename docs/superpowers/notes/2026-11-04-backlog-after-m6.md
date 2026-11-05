# Backlog after M6 (owner requests, 2026-11-04)

Recorded from the design session so nothing is lost. Each item becomes a task in the next milestone plan.

## M7 — one design everywhere ("Um só desenho", mock: `public/mock/variants.html` version F, `player.html`)
- Landing: headline "The tournament software with fair seats", scrolling card-art mosaic, logo (point-down triangle,
  gear rotating around the S) above the small "Grindin Station", waiting-list form, seat board + "why it is fair",
  upcoming events with banners/organiser and **View event / Register** buttons.
- Top bar: logo beside the name, **EN / PT / ES** language switch (add `es.yml`).
- Organizer tournament page as **tabs**: Overview · Roster · Rounds · Judge Center (badge) · Staff · Settings; header
  keeps "View public page" + the state action. Tabs are routes (Turbo), so URLs are shareable.
- Organizer "My tournaments" cards with the event banner; sign-in/sign-up card with the logo, explicit
  "create an account with any e-mail"; all legacy pages (lists, forms, circuits, leagues, notifications, account)
  on the same components.
- Player phone pages: logo beside the name, event name once; the event page shows only the player's own data
  (no enrolled list, no counts, no others' decklists) plus **their decklist link** (Moxfield/Archidekt/any) editable
  until round 1 is published; pairings with a **search box** and the player's own table first and highlighted;
  grey line-icon trophy; multiplayer screens identical with seats 1·2·3·4.
- Public event page (no login): only the count of enrolled players; the list with decklists is staff-only.

## M8 — multiplayer pairing modes (owner: "like TopDeck") — DONE 2026-11-05 (spec `../specs/2026-11-05-m8-pairing-modes.md`; "true Swiss" not offered: it is plain Swiss)
- Event setting `pairing_mode` for multiplayer events, chosen in Settings: **Swiss pods** (by points, today's
  default), **Random pods** (ignore points every round), **Power pods** (strict top-down by points, no spread), and
  TopDeck's "true Swiss" if we find it differs from Swiss pods. Last-round behaviour per mode documented.
- **Seat fairness is independent of the mode**: `SeatAssigner` (seat 1 to whoever had it least, cheapest order,
  seeded ties) and `RematchRepair` run for every mode; the simulation gate (`grindin:simulate`) must pass for each.
- The organizer can change the mode until the swiss starts (locked with the structure).

## M9 — admin dashboard (owner: "seguir tudo o que se passa") — DONE 2026-11-05 (spec `../specs/2026-11-05-m9-admin-dashboard.md`; 4xx/5xx rates not tracked, error counts stand in)
- A site-admin role (separate from event organizer; the first admin is promoted by a rake task, never by sign-up).
- `/admin` with: counts and trends (registered players, organizers, tournaments by state and format, events per
  month, players per event), tournament-day health (open judge calls, disputed tables, rounds running late,
  self-reports pending), errors (last exceptions with request id, 4xx/5xx rate, CSP violation reports, rate-limit
  hits), and an **audit log** of sensitive actions (sign-ins and failures, password/e-mail changes, role changes,
  result corrections on closed rounds, undo round, drops/no-shows, event state changes, staff added/removed,
  deletions) with who/when/what/ip.
- Implementation notes: an `audit_events` table written from the services/controllers that already know the
  actor (`Current.user`), not from callbacks; errors via a Rails error subscriber (`Rails.error`) into an `errors`
  table with grouping; counters from plain SQL, cached 60 s; pages built with the same components (cards,
  compact tables, chips), charts as simple inline SVG sparklines. Read-only except "resolve" on an error group.
- Retention: audit 12 months, errors 90 days, CSP reports 30 days; a nightly job trims them.

## Smaller
- Organizer card copy for 1v1 ("Reported by …") in pt; ~~`es.yml`~~ (done in M7: `config/locales/es.yml`, kept key for key by `test/i18n_parity_test.rb`).
- Cut-round names for multiplayer into i18n (1v1 already is).
- No-JS fallback for 1v1 points defaults on the create form.

## M10 — Export tournament data for official reporting (added 2026-11-04) — DONE 2026-11-05 (spec `../specs/2026-11-05-m10-export.md`)

Stores must report results to Wizards (EventLink) or risk penalties, so without an export they have little reason to use Grindin. Requirement from the user: an "Export" option on the organizer tournament page that produces the data needed to report the event on the official platforms (Wizards EventLink; also whatever the local store-reporting flow needs).

Open research before specifying: what EventLink actually accepts today (as of 2020 it has no import of third-party results, only manual entry; Companion runs sanctioned events itself). If no import exists, the export must at least make manual entry fast: a one-page results sheet per round (table, players, Wizards account e-mail/ DCI-less identifier, result) plus final standings, as CSV + printable PDF, and a Melee/TopDeck-compatible CSV for premier/third-party platforms. Decide after checking the current EventLink docs.

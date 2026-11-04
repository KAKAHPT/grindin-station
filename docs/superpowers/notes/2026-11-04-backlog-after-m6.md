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

## M8 — multiplayer pairing modes (owner: "like TopDeck")
- Event setting `pairing_mode` for multiplayer events, chosen in Settings: **Swiss pods** (by points, today's
  default), **Random pods** (ignore points every round), **Power pods** (strict top-down by points, no spread), and
  TopDeck's "true Swiss" if we find it differs from Swiss pods. Last-round behaviour per mode documented.
- **Seat fairness is independent of the mode**: `SeatAssigner` (seat 1 to whoever had it least, cheapest order,
  seeded ties) and `RematchRepair` run for every mode; the simulation gate (`grindin:simulate`) must pass for each.
- The organizer can change the mode until the swiss starts (locked with the structure).

## Smaller
- Organizer card copy for 1v1 ("Reported by …") in pt; `es.yml`.
- Cut-round names for multiplayer into i18n (1v1 already is).
- No-JS fallback for 1v1 points defaults on the create form.

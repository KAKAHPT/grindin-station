# M7 — one design everywhere (spec, 2026-11-04)

The owner approved a reference design in the mocks under `public/mock/` (git-ignored, on this Mac):
`variants.html` (version **F**: landing, organizer "My tournaments", organizer tournament page with tabs, edit pop-up,
sign-in), `player.html` (ten phone screens, 1v1 and pods of four), `standings.html` and `event-pairings.html`
(desktop public pages for visitors and signed-in players), `logos-rich.html` (the mark). This spec turns them into
requirements. Where the mock and this spec differ, this spec wins.

## 1. Design system (one set of pieces, used by every page)
- Palette A dark only, tokens as in `app/assets/tailwind/application.css`. Fonts Sora (display) + Manrope (body).
- **Mark**: inline SVG, point-down teal triangle slab, dark gear, teal S; the gear rotates (CSS, 14 s, only in
  the top bar and the event-header corner; nowhere else; honours `prefers-reduced-motion`). Favicon and app icon
  from the same SVG (static). The mark replaces the current green square everywhere.
- **Top bar** (every layout): mark + "Grindin Station", nav Events · Rankings · About, language switch **EN / PT / ES**
  (sets the locale cookie; keeps the current page), then Sign in or the user chip + Account (+ "Organizer mode"
  chip for organizers).
- **Event header card** (`evhead`): cover image blurred behind (event cover; neutral surface when none), eyebrow
  (state · format · live), title, one info line, actions on the right, and the mark half out of the top-right
  corner. Used on public event/pairings/standings and on the organizer tournament page.
- **Cards and tables**: table header rows and card title bands darker than the body (`rgb(0 0 0/.28)` / `.22`);
  pod/table card headers likewise. Squared `.btn` (primary teal gradient, secondary, ghost, danger), flat 4 px chips,
  segmented control, tabs (underline teal).
- **Movement arrows** in standings: tiny, near-background grey, ▲n / ▼n / – since the last round. No colours.
- **Trophy**: grey line icon. No emoji anywhere.
- No Flowbite purple/orange buttons, no gray/dark: legacy classes, no `inter` font, anywhere.

## 2. Landing (`/`)
- Scrolling, slightly tilted mosaic of card art behind the hero (48 art crops shipped in
  `app/assets/images/landing/`, with the Wizards fan-content attribution line in the footer), 90 s loop,
  low blur, vignette keeps the text clean; static for reduced motion.
- Mark above the small "GRINDIN STATION" eyebrow, then **"The tournament software with fair seats."**, then
  "Built for multiplayer. Open to every format. Pairings, standings and tables update live on every phone in the
  room.", buttons **Upcoming events** / **Organise a tournament**, then the waiting-list card ("Organising is by
  invitation for now", name + e-mail + Join → `waitlist_signups` table, flash thanks, organizer e-mail notified if
  SMTP is set).
- Seat board (Anne's 4 rounds, English names, different opponents every round, cost column, totals "fair") with
  the sentence under it, and "Seats are weighted, not drawn" with the four numbered steps.
- **Upcoming events**: date block, name, format line, organizer (avatar initials + name), enrolled count, state
  chip, **View event**, and **Register** when registration is open; the event cover blurred behind each row.
- Signed-in users see the same page; organizers also get a "My tournaments" shortcut in the top bar.

## 3. Public event pages (`/t/:slug`, `/pairings`, `/standings`)
- All three under the event header card; segmented Event · Pairings · Standings; "My table" button when the
  viewer is enrolled.
- **Event**: "About" (when, where with map link, price, format line, description/rules) and, for a visitor,
  "Registration" with only the counts (enrolled, waitlist) and "Sign in to register" / "Register"; for an enrolled
  player, "You": enrolled/checked-in chips, **decklist link** (any URL; editable until round 1 is published; the
  model already locks it) with Save, and Cancel registration. **No list of other players, no others' decklists.**
- **Pairings**: round selector + time left, search box (client-side filter), the viewer's own table first and
  highlighted with "Your table" and "You"; darker table headers; score next to the winner (1v1); grey trophy.
- **Standings**: columns per format as today, **no Seats column** for anyone; movement arrows from a per-round
  snapshot (`standings_snapshots`: event, round number, participant, rank; written when a round closes); the
  viewer's row highlighted with "You"; help text per format.
- Phone: same pages, one column; the top bar shows the mark beside the name and the viewer; the event name appears
  once (in the header card).

## 4. Organizer
- **My tournaments**: cards with the cover blurred at the top, state chip, date · city · enrolled, buttons
  Rounds / Roster / Edit; Active · Past segmented; **New tournament** primary.
- **Tournament page** = event header card + **tabs** as routes: Overview (counters + Format + Lately),
  Roster (today's roster), Rounds (today's round page, with the round selector), Judge Center, Staff, Settings
  (the edit form, format locked, structure, results settings, Cancel event). Header actions: View public page +
  the state action (Open/Close registrations, Start Swiss…). Judge Center tab shows the open-calls count.
- New tournament form, leagues and circuits pages, notifications, account: same components; no redesign beyond
  consistency (lists as cards/tables, forms as the Settings tab).

## 5. Auth
- Sign in / sign up / forgot / reset as one centred card with the mark and "GRINDIN STATION" above the title,
  e-mail + password first, Google/Discord below, then "New here? Create an account with any e-mail · No Google or
  Discord needed. You can link them later from your account.", Forgot password below.

## 6. Languages
- `config/locales/es.yml` complete (same keys as en/pt); the switch stores `locale` in a cookie (and keeps the
  `?locale=` param behaviour); `I18n.available_locales = [:en, :pt, :es]`; broadcasts render per locale as today.

## 7. Done means
- Every page in the inventory (`public/mock` session: 27 desktop + 10 phone) uses the same pieces; a regenerated
  inventory sheet shows no legacy styling; Lighthouse ≥ 90 on the four public pages; all tests green; the owner's
  mocks reproduced screen by screen.

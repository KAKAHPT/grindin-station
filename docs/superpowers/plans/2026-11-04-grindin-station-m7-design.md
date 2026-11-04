# Grindin Station M7 — one design everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every page (public, player phone, organizer, auth) uses the approved design: mark, top bar with language switch, event header card, darker table bands, tabs on the organizer tournament page, landing with the fair-seats story and waiting list, player-only data on the event page, movement arrows in standings, Spanish.

**Architecture:** One `application` layout (top bar partial + optional event header partial + `yield`), used by public, play and organizer pages; `play` and `public` layouts become thin wrappers or are removed; shared partials under `app/views/shared/` (`_mark.html.erb`, `_topbar.html.erb`, `_event_header.html.erb`, `_tabs.html.erb`, `_movement.html.erb`); Tailwind component classes in `app/assets/tailwind/application.css` (`.band`, `.evhead`, `.tab`, `.seg`); standings snapshots table for arrows; `waitlist_signups` table; `es.yml`.

**Tech Stack:** Rails 8.1, Tailwind 4, Hotwire, Minitest + Capybara, Playwright (inventory screenshots in `/private/tmp/claude-501/.../scratchpad/demo-video/inventory.js`, reusable).

**Spec:** `docs/superpowers/specs/2026-11-04-m7-one-design.md` (binding; mocks in `public/mock/`).

## Global Constraints

- Dark-only palette A; no new colours; no Flowbite button classes; copy in en, pt **and es** for every new key.
- Behaviour unchanged except where the spec says (event page visibility, decklist lock already in place, arrows).
- Prosopite raises in tests; Lighthouse ≥ 90 on the four public pages at the end; full suites green; never run tests in two checkouts at once.
- Keep the organizer round page (pods, results, live) as it is functionally; only its chrome changes (header card, tab).

## Review Focus

1. A visitor must never see other players' names or decklists on `/t/:slug` (Task 4 test), while staff still see the roster.
2. Arrows must be computed from the snapshot of the previous closed round, never from live standings (Task 4 test with a round close).
3. The language switch must keep the user on the same page and persist across requests (Task 6 test).
4. Organizer tabs are routes: direct URLs to Roster/Rounds/Judge Center/Staff/Settings render inside the tabbed page and the back button works (Task 5 tests).
5. The landing mosaic must not block first paint or cost Lighthouse (Task 2: lazy images, `content-visibility`, Lighthouse check).

---

### Task 1: Design foundation (mark, top bar, event header, bands, tabs, one layout)

**Files:**
- Create: `app/views/shared/_mark.html.erb` (inline SVG, `rotating: true|false`), `app/views/shared/_topbar.html.erb`, `app/views/shared/_event_header.html.erb` (locals: event, eyebrow, title, line, actions block), `app/views/shared/_tabs.html.erb`, `app/assets/images/mark.svg` (static), favicon/app icon from it
- Modify: `app/views/layouts/application.html.erb` (top bar partial; `content_for :event_header`), `app/views/layouts/play.html.erb` and `public.html.erb` (render the same top bar; keep their body wrappers), `app/assets/tailwind/application.css` (`.band`, `.evhead`, `.evhead-corner`, `.tab`, `.seg`, darker `th` default, gear keyframes), `app/helpers/palette_helper.rb` (helpers `band_classes`, `tab_classes`), remove the green square brand everywhere (`grep -rn "bg-gradient-to-br\|brand" app/views/layouts`)
- Test: `test/controllers/layout_test.rb` (every layout renders the mark once in the top bar, rotating only there), view test for `_event_header` with and without cover

**Interfaces:**
- Produces: `render "shared/event_header", event:, eyebrow:, title:, line:, actions: capture { … }`; CSS classes `band`, `evhead`, `tab`, `tab-on`, `seg`, `seg-on`.

- [ ] Tests first (layout renders mark + language switch placeholder + nav), implement, `bin/rails tailwindcss:build`, run `bin/rails test test/controllers`, screenshot `/t/demo-cup` and `/organizer/tournaments` for the report. Commit `feat(design): mark, top bar, event header, bands, tabs`.

### Task 2: Landing page

**Files:**
- Create: `app/controllers/pages_controller.rb#home` (root), `app/views/pages/home.html.erb`, `app/assets/images/landing/c1..c48.jpg` (copy from `public/mock/art/`), `app/models/waitlist_signup.rb` + migration (`name`, `email`, `created_at`), `app/controllers/waitlist_signups_controller.rb#create` (rate-limited 5/10 min per IP), `app/mailers/waitlist_mailer.rb` (optional, when SMTP configured)
- Modify: `config/routes.rb` (`root "pages#home"`; events index stays at `/events`), locales en/pt/es (`landing.*`), footer attribution
- Test: `test/controllers/pages_controller_test.rb` (hero copy, upcoming events with Register only when open, waitlist create + rate limit, hidden events excluded), system test: landing renders with no console errors and the seat board shows "Anne"

- [ ] Tests, implement (mosaic as `<img loading="lazy">` tiles in a `content-visibility:auto` container, CSS animation 90 s, reduced-motion static), Lighthouse on `/` ≥ 90, commit `feat: landing page with the fair-seats story and waiting list`.

### Task 3: Standings snapshots and movement arrows; grey trophy

**Files:**
- Create: migration `standings_snapshots` (event_id, round_number, event_participant_id, rank; unique on [event_id, round_number, event_participant_id]), `app/models/standings_snapshot.rb`, `app/services/standings/snapshot.rb` (`call(event, round)` writes ranks from `standings_for` order), `app/views/shared/_movement.html.erb`
- Modify: `app/models/round.rb` (`round_finished` → snapshot after close, before advancing), `app/controllers/organizer/rounds_controller.rb#destroy` (delete the snapshot of the undone round), `EventParticipant` (`movement_since_last_round` from the two latest snapshots), standings views (public + organizer) and feeds (`movement` integer or null), trophy icon in `app/assets/images/icons.svg` (grey line icon) used in pairings/pod cards
- Test: `test/services/standings/snapshot_test.rb`, feed test, controller test (arrow text ▲1 / ▼2 / –)

- [ ] Commit `feat: standings movement since the last round; grey trophy`.

### Task 4: Public event pages per spec §3 (desktop and phone)

**Files:**
- Modify: `app/views/play/events/show.html.erb` (+ `_about`, `_you`, `_registration` partials; visitor sees counts only; enrolled player sees own chips + decklist form + cancel), `app/controllers/play/events_controller.rb` (+ `update_decklist` route or reuse `EventParticipantsController#update`), `app/views/play/pairings/show.html.erb` + `_table.html.erb` (search box Stimulus `pod_filter` reuse; own table first), `app/views/play/standings` / `event_participants/index.html.erb` (header card, arrows, no seats, "You" row), `app/views/play/tables/*` (header), `app/views/layouts/play.html.erb` (phone top bar: mark + name + viewer), locales en/pt/es
- Test: `test/controllers/play/events_controller_test.rb` (visitor: no other names/decklists; player: own decklist form; staff: unchanged roster link), pairings (own table first), standings (no seats, arrows), system test on phone viewport for the event page

- [ ] Commit `feat: public event pages — header card, player-only data, search, arrows`.

### Task 5: Organizer pages — tournaments list, tabbed tournament page, forms, judge center, staff, leagues/circuits

**Files:**
- Modify: `app/views/organizer/tournaments/index.html.erb` (+ `_tournament_card`), `show.html.erb` → tabbed shell (`_tabs` with routes: show=Overview, `event_participants` (Roster), `rounds/:latest` (Rounds), `judge_calls`, `staff`, `edit` (Settings)); each of those controllers' views render inside the shell via `content_for :event_header` + `content_for :tabs`; `_tournament_actions*.html.erb` (header actions only: View public page + state action), `app/views/organizer/{judge_calls,staff}/index.html.erb`, `tournaments/_form.html.erb` (Settings tab look), `new.html.erb`, `organizer/leagues/*`, `organizer/circuits/*` (components only), remove every Flowbite purple/orange class in `app/views/organizer`
- Test: `test/controllers/organizer/tournaments_controller_test.rb` (tabs present, active tab per route, legacy classes absent: `assert_select "[class*=purple]", 0`), judge center/staff render in the shell

- [ ] Commit `feat: organizer pages on the design — tabs, cards, settings`.

### Task 6: Auth and account pages; language switch; Spanish

**Files:**
- Modify: `app/views/sessions/new.html.erb`, `registrations/new.html.erb`, `passwords/{new,edit}.html.erb`, `accounts/show.html.erb`, `notifications/index.html.erb` (card with mark; copy per spec §5), `app/controllers/application_controller.rb#switch_locale` (cookie `locale`, param wins and sets the cookie), `app/controllers/locales_controller.rb#update` (POST, `redirect_back`), `config/application.rb` (`available_locales %i[en pt es]`), create `config/locales/es.yml` (complete; translate from pt with en as reference; keep "Draw", product names), `app/views/shared/_topbar.html.erb` (switch)
- Test: locale switch persists (cookie) and keeps the page; `es.yml` key parity test (`I18n::Tasks` not installed: write a minitest that flattens en/pt/es keys and asserts equality); auth pages render the mark and the e-mail sign-up copy

- [ ] Commit `feat: auth pages, language switch and Spanish`.

### Task 7: Sweep, inventory and verification

**Files:**
- Modify: anything left with legacy classes (`grep -rn "purple\|orange-700\|dark:\|gray-" app/views | wc -l` → 0), `CLAUDE.md` (Frontend: design pieces, layouts, locales), `README.md`
- Run: inventory script (regenerate the two sheets to `docs/superpowers/notes/inventory-m7-{desktop,mobile}.png`), `bin/rails grindin:lighthouse`, full `bin/rails test` + `test:system`, `bin/rubocop`

- [ ] Commit `docs: M7 inventory and Lighthouse`.

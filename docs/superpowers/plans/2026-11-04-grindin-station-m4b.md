# Grindin Station M4b — tournament-day hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the deferred items from M2–M4 that would bite during the M5 pilot: live public pairings, the organizer's winner selection surviving live refreshes, clocks rendered before JS, Portuguese copy, and the legacy public routes honouring hidden events.

**Architecture:** Reuse the existing Turbo Stream machinery (`LiveBroadcasts`, `Live::BroadcastRoundJob`, `Live::BroadcastPodJob`): add one public per-event stream that morph-refreshes `/t/:slug/pairings`. Client-side fixes stay inside the existing Stimulus controllers. Hidden-event rules move from `PublicEvent#find_public_event!` into a reusable check used by the legacy `/tournaments/:id/...` controllers.

**Tech Stack:** Rails 8.1, Turbo 8 (morph refresh, Turbo Streams), Stimulus, Minitest + Capybara (headless Chrome).

**Spec:** `docs/superpowers/specs/2026-10-14-grindin-station-design.md` (§7 "Público sem login: … pods da ronda atual"; §5.5; §6 draft events only for staff).

## Global Constraints

- Dark-only palette A; copy in `config/locales/{en,pt}.yml`; all user-visible strings translated in both.
- Prosopite raises in test: no N+1.
- Broadcasts render once per locale (`LiveBroadcasts.each_locale`); the originating request is skipped via `request_id`.
- Never run the test suite in two checkouts at once (shared test DB).
- Frozen string literals, double quotes, `params.expect`.

## Review Focus

1. A visitor on `/t/:slug/pairings` for an *earlier* round (`?round=N`) must not be flipped to the latest round by a refresh — a morph refresh re-renders the same URL, so the round stays (Task 1 test).
2. A staff member who selected a winner on a pod card and then receives a refresh (another table reported) must keep the selection; if that pod was completed meanwhile, the selection must clear, not submit (Task 2 test).
3. Draft/canceled events must be 404 for visitors on every public URL, including the legacy `/tournaments/:id/rounds/:id` and `/tournaments/:id/event_participants` pages (Task 3 test).
4. The pairings page of a draft event must never broadcast to visitors anything (it 404s, so no subscription; Task 3 covers the page; Task 1 keeps the stream name per event id, which is unguessable).
5. The clock must show the right value at first paint even when JS is slow (Task 2 test asserts non-empty server text).

---

### Task 1: Live public pairings

**Files:**
- Modify: `app/models/concerns/live_broadcasts.rb`
- Modify: `app/jobs/live/broadcast_round_job.rb`, `app/jobs/live/broadcast_pod_job.rb`
- Modify: `app/views/play/pairings/show.html.erb`, `app/controllers/play/pairings_controller.rb` (comment), the play layout if it does not `yield :head`
- Modify: `CLAUDE.md` (Background Jobs: "Public pairings are not live yet" → are live), `README.md` if it says the same
- Test: `test/jobs/live/broadcast_pairings_test.rb` (new), `test/controllers/play/pairings_controller_test.rb`, `test/system/live_table_test.rb`

**Interfaces:**
- Produces: `LiveBroadcasts.pairings_stream(event_id, locale = I18n.locale)` → `"pairings:#{event_id}:#{locale}"`; `LiveBroadcasts.refresh_pairings(event_id, request_id: nil)` (one `broadcast_refresh_to` per locale, like `refresh_round`).

- [ ] **Step 1: Failing job test** `test/jobs/live/broadcast_pairings_test.rb`: performing `Live::BroadcastPodJob.perform_now(pod_id: pod.id)` for a pod of a published round broadcasts a refresh on `LiveBroadcasts.pairings_stream(event.id, :en)` and on `:pt` (use `assert_turbo_stream_broadcasts` from `Turbo::Broadcastable::TestHelper`, count: 1 each); performing `Live::BroadcastRoundJob.perform_now(round)` does the same; a pod of an unpublished round broadcasts nothing on the pairings stream (`assert_no_turbo_stream_broadcasts`).
- [ ] **Step 2: Run, verify it fails** (`bin/rails test test/jobs/live/broadcast_pairings_test.rb`).
- [ ] **Step 3: Implement** `pairings_stream` and `refresh_pairings` in `LiveBroadcasts`; call `refresh_pairings(round.event_id, request_id:)` in `BroadcastRoundJob#perform` right after `refresh_round` (always, not only when `tables:`), and in `BroadcastPodJob#perform` after `broadcast_state` (always).
- [ ] **Step 4: Failing controller test** in `pairings_controller_test.rb`: the page contains `turbo-cable-stream-source` whose `signed-stream-name` decodes to the pairings stream (compare with `Turbo::StreamsChannel.signed_stream_name(LiveBroadcasts.pairings_stream(event.id, :en))`) and `meta[name="turbo-refresh-method"][content="morph"]`; and for `?round=1` (earlier round) too.
- [ ] **Step 5: Implement** in `show.html.erb`: `<% turbo_refreshes_with method: :morph, scroll: :preserve %>` and `<%= turbo_stream_from LiveBroadcasts.pairings_stream(current_event.id) %>` (the play layout must `yield :head` for the meta tags — check `app/views/layouts/play.html.erb`; add `<%= yield :head %>` inside `<head>` if missing). Update the controller comment ("follows the event's pairings stream").
- [ ] **Step 6: Failing system test** in `live_table_test.rb`: a visitor (not signed in) opens `/t/:slug/pairings`, a staff result is applied in the test process (same way the existing live test applies the staff result), and `within("[data-pairings]")` the table turns "Completed" with the winner's trophy without any page reload (assert the page's `data-round-number` element is the same DOM node: e.g. set `window.__marker = 1` with `execute_script` before and read it after). Also: a visitor on `?round=1` of a two-round event stays on round 1 after a refresh (assert `[data-round-number]` text).
- [ ] **Step 7: Run** `bin/rails test test/jobs/live test/controllers/play/pairings_controller_test.rb` and `bin/rails test test/system/live_table_test.rb` → PASS. Update CLAUDE.md/README.
- [ ] **Step 8: Commit** `feat: public pairings update live`.

### Task 2: Organizer round page: selection survives refresh, clocks render server-side, pt copy

**Files:**
- Modify: `app/javascript/controllers/pod_result_controller.js`, `app/javascript/controllers/round_timer_controller.js` (only if needed)
- Modify: `app/views/organizer/rounds/show.html.erb` (clock initial text), `app/views/play/timers/show.html.erb` (clock initial text), `app/helpers/rounds_helper.rb` or `PaletteHelper` (new `clock_text` helper)
- Modify: `config/locales/pt.yml`
- Test: `test/system/organizer_round_flow_test.rb`, `test/controllers/organizer/rounds_controller_test.rb` (or wherever the round page is tested), `test/controllers/play/timer_test.rb`, `test/helpers/rounds_helper_test.rb` (new)

**Interfaces:**
- Produces: `clock_text(started_at, minutes)` → `"mm:ss"` remaining (zero-padded minutes as in `big_timer_controller.js`), `"00:00"` when time is up; `nil` minutes (untimed) → elapsed `"mm:ss"`.

- [ ] **Step 1: Failing system test** in `organizer_round_flow_test.rb`: "a winner selection survives a live refresh": organizer opens the round page, clicks Player X's row on Table 2 (the confirm row shows "Player X wins"), then the test broadcasts `Turbo::StreamsChannel.broadcast_refresh_to(LiveBroadcasts.round_stream(round.id, :en))` (no request_id, so the page refreshes), waits for the morph (e.g. another table's state changed in the DB before the broadcast and assert it appears), and asserts the row still has `data-selected="true"` and the confirm label still reads "Player X wins". Second case: the selected pod was completed by staff before the refresh → after the morph no row is selected and the confirm row is hidden.
- [ ] **Step 2: Run, verify it fails.**
- [ ] **Step 3: Implement** in `pod_result_controller.js`: remember the selected seat (`this.selectedSeat`) in `mark`/`clear`; in `connect` add a `turbo:morph` listener on `document` (bound once, removed in `disconnect`) that, when `this.selectedSeat` is set, finds the row target with that seat and the win form for it: if both exist → `mark(row)`, else → `clear()`.
- [ ] **Step 4: Failing helper test** `clock_text(Time.current - 10.minutes, 50)` → `"40:00"`; `clock_text(Time.current - 60.minutes, 50)` → `"00:00"`; `clock_text(Time.current - 90.seconds, nil)` → `"01:30"`; freeze time with `travel_to`.
- [ ] **Step 5: Implement** `clock_text` in `app/helpers/rounds_helper.rb` (create if absent) and render it as the initial text of the organizer round clock element (`organizer/rounds/show.html.erb`, the element with `data-controller="round-timer"`; note its `round-time` value is seconds — convert) and of the big timer `<p class="clock">`. Controller test: the response body's clock element has non-empty text matching `/\A\d{2}:\d{2}\z/` (round page as organizer; `/t/:slug/timer` as visitor).
- [ ] **Step 6: Portuguese copy:** in `config/locales/pt.yml` translate `player_wins` ("%{name} ganha"); then diff the `play.*`, `organizer.*`, `roster.*`, `pods.*` sections against `en.yml` and translate any value that is still identical English prose (not proper nouns/brand words like "Draw" — the user chose "Draw" as the button label in both languages). Keep a list of the keys you changed in the report.
- [ ] **Step 7: Run** `bin/rails test test/helpers test/controllers/organizer test/controllers/play/timer_test.rb` and `bin/rails test test/system/organizer_round_flow_test.rb` → PASS. `bin/rubocop` clean.
- [ ] **Step 8: Commit** `fix: winner selection survives live refresh; clocks render server-side; pt copy`.

### Task 3: Legacy public routes honour hidden events

**Files:**
- Modify: `app/controllers/concerns/public_event.rb`, `app/controllers/rounds_controller.rb`, `app/controllers/pods_controller.rb`, `app/controllers/event_participants_controller.rb`, `app/controllers/tournaments_controller.rb` and `app/controllers/leagues_controller.rb` if their `show` loads by id without the check
- Modify: `config/routes.rb` (public `resources :rounds`/`:pods` → `only: %i[index show]` under both `/tournaments` and `/leagues`; keep `event_participants` as is)
- Test: `test/controllers/play/hidden_events_test.rb` (extend), `test/controllers/rounds_controller_test.rb` if present

**Interfaces:**
- Produces: `PublicEvent#ensure_public!(event)` → raises `ActiveRecord::RecordNotFound` when `event.state` is draft/canceled and `current_user&.staff_role_for(event)` is nil; `find_public_event!` uses it.

- [ ] **Step 1: Failing tests** in `hidden_events_test.rb`: for a draft and a canceled tournament with one published round and one pod: `GET /tournaments/:id/rounds/:round_id`, `GET /tournaments/:id/rounds/:round_id/pods/:pod_id`, `GET /tournaments/:id/event_participants` → 404 for a visitor and for a signed-in non-staff user; 200 for the organizer. Also `GET /tournaments/:id/rounds` → 404 for visitors.
- [ ] **Step 2: Run, verify it fails.**
- [ ] **Step 3: Implement** `ensure_public!` and call it in each legacy controller after loading the event (include `PublicEvent`). Restrict the public `rounds`/`pods` routes to `only: %i[index show]`; run `bin/rails routes | grep -v organizer | grep -E "rounds|pods"` to confirm no other public actions remain, and grep views for helpers of removed routes (`new_tournament_round_path` etc.) — remove any dead links you find only if they point at removed routes.
- [ ] **Step 4: Run** `bin/rails test test/controllers` → PASS; `bin/rubocop` clean.
- [ ] **Step 5: Commit** `fix: legacy public event pages are hidden for draft and canceled events`.

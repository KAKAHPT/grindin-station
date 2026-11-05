# M12 Player Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the public profile's events section as a filtered, sortable table with a stats band, achievements, most played commanders and per-event details, plus a free-text team tag.

**Architecture:** `Profiles::History` grows its `Row` with the fields the table and details need (fixed query count); a new `Profiles::Summary` derives the band numbers from rows. The view renders everything server-side with `data-*` attributes; one Stimulus controller (`profile_events`) filters, sorts, expands and recomputes the band from the visible rows. `users.team` is a plain column edited in `/account`.

**Tech Stack:** Rails 8.1, Hotwire/Stimulus, Tailwind 4, Minitest + Capybara system tests, Prosopite.

**Spec:** `docs/superpowers/specs/2026-11-05-m12-player-profile.md` (the approved mock is `public/mock/profile-events.html`, table variant; the mock is a reference, not something to ship).

## Global Constraints

- Grey only (spec D12): band `bg-surface-raised`, numbers `text-ink`, labels `text-muted` uppercase `text-[10.5px] tracking-[0.06em]`; achievements box `border border-line-2 rounded-[10px] bg-surface`; tags `border border-line-2 rounded text-muted uppercase text-[10px]`; the open "+" is `bg-ink text-ground`; the only accent is the seat-1 cell in the detail row. `grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0.
- M7 pieces: `card`, `ctable`, `button_classes(:secondary, size: :sm)`, `.field`; new rules only in a `/* profile */` block of `app/assets/tailwind/application.css`.
- Profile main column widens to `max-w-2xl`: `app/views/layouts/public.html.erb` gets `content_for?(:wide_main) ? "max-w-2xl mx-auto px-4 pt-4 pb-12"` between the existing two branches; the profile sets `content_for :wide_main, "1"`.
- Exact figures: win rate = wins ÷ (wins+losses+draws), conversion = made_cut ÷ events, both rounded to whole percent, "–" when the denominator is 0. Default 6 rows visible. Top-cut tag text `Top %{size}`. Year buttons: "All" + every year with a row, newest first. Season select: "All seasons" + circuit names of the rows, A–Z.
- `made_cut` = the participation has a `Seating` in a `SingleEliminationRound` pod of that event, or an `Advance` result in a `SingleEliminationRound`. `cut_size` = `event.top_cut_size_or_suggested` for tournaments (nil for leagues or when 0).
- Copy in en/pt-PT/es from spec §6; `test/i18n_parity_test.rb` passes. Only task files committed (`git commit -- <paths>`); rubocop clean.
- Prosopite: the profile page must not add per-row queries (`Profiles::History` stays a fixed number of queries; the view reads only preloaded data).

## Review Focus

1. A player with a bye in a cut round (Advance, no SE seating) must count as `made_cut` (Task 1 test).
2. A 1v1 event row must show "1v1 · no seats" in the detail and contribute no seats to the band (Task 3 test).
3. With JavaScript off the whole table and the server totals must render; the "More" footer must not hide rows server-side (Task 3 controller test asserts all 12 rows present).
4. Filtering to zero rows must show "No events match." and "–" for the rates, not NaN (Task 4 system test).
5. The team tag must never render for a blank team and must be cleared by anonymisation (Task 2 tests).

---

### Task 1: History rows and Summary

**Files:**
- Modify: `app/queries/profiles/history.rb`
- Create: `app/queries/profiles/summary.rb`
- Test: `test/queries/profiles/history_test.rb`, `test/queries/profiles/summary_test.rb` (create)

**Interfaces:**
- Produces: `Profiles::History::Row` with the existing fields plus `games` (Integer), `made_cut` (Boolean), `cut_size` (Integer or nil), `commander` (String or nil), `organizer_name` (String), `format_line` (String), `season` (String or nil), `round_seats` (Array<Integer> ordered by Swiss round number, or nil for 1v1).
- Produces: `Profiles::Summary.call(rows) -> Data(events:, top_cuts:, win_rate:, conversion_rate:, wins:, top4:, commanders:)` where rates are Integer percents or nil and `commanders` is `[[name, count], …]` (top 4 by count, then name A–Z; rows with nil commander are skipped).
- Consumes: `EventParticipant#commander_text`, `Tournament#top_cut_size_or_suggested`, `Event#circuit` (`belongs_to :circuit, optional: true`), `Event#event_organizer`, the format label logic from `EventsHelper#event_format_label` (move the pure part into `Event#format_label`-free helper call? No: compute `format_line` in the query with `I18n.t`, the same keys `play.events.format_badge`/`play.header.multiplayer`).

- [ ] Step 1: Failing tests in `history_test.rb`: a finished Top-4 tournament where the user reached the single-elimination round → `made_cut == true`, `cut_size == 4`, `round_seats` equals the seats in Swiss round order, `commander` from `decklist: "Kinnan, Bonder Prodigy"`, `season` = the circuit name when the event belongs to one and nil otherwise, `games == wins + losses + draws`; a user with an `Advance` in a `SingleEliminationRound` and no SE seating → `made_cut == true`; a 1v1 event → `round_seats nil`. Failing tests in `summary_test.rb` with hand-built rows (`Row.new(...)`): the numbers above for 3 rows (two cuts, one win, 2 games won of 8 → win_rate 25, conversion 67), empty rows → all zero and nil rates, commanders top 4 ordering.
- [ ] Step 2: Run both files; expect failures (unknown keyword).
- [ ] Step 3: Implement: `includes(:event => [:circuit, :event_organizer])` in `finished_participations`; two new grouped queries (`cut_ids` from `Seating.joins(pod: :round).where(event_participant_id: ids, rounds: { type: "SingleEliminationRound" }).distinct.pluck(:event_participant_id)` ∪ Advance results in SE rounds from the preloaded `results` with their rounds; `round_seats` from `Seating.joins(pod: :round).where(event_participant_id: ids, rounds: { type: "SwissRound" }).where("rounds.finished_at IS NOT NULL OR rounds.published = TRUE").pluck(:event_participant_id, "rounds.number", :order)` grouped and sorted by number). `Summary` as a plain Ruby object.
- [ ] Step 4: `bin/rails test test/queries`; expect PASS. Check the query count in the history test with `assert_queries_count` if the helper exists, else document the count in the report.
- [ ] Step 5: Commit `feat(m12): profile history rows with cut, commander, season and round seats; summary`.

### Task 2: Team field

**Files:**
- Create: `db/migrate/<ts>_add_team_to_users.rb`
- Modify: `app/models/user.rb` (normalize + length validation), `app/controllers/accounts_controller.rb` (permit `:team`), `app/views/accounts/show.html.erb` (field after Country with datalist), `app/services/accounts/anonymize.rb` (`team: nil`), `config/locales/{en,pt,es}.yml` (`accounts.show.team`, `accounts.show.team_hint`, attribute label)
- Test: `test/models/user_test.rb`, `test/controllers/accounts_controller_test.rb`, the anonymize test file (find it under `test/services/accounts/`)

**Interfaces:**
- Produces: `users.team` string (nullable), `User#team`, `User.team_suggestions -> Array<String>` (`where.not(team: nil).distinct.order(:team).limit(50).pluck(:team)`).

- [ ] Step 1: Failing tests: team of 30 chars valid, 31 invalid, `"  Porto Grinders "` normalised to `"Porto Grinders"`, blank → nil; PATCH `/account` with `team` persists; the account page has `<datalist id="team-suggestions">` with another user's team; anonymise clears `team`.
- [ ] Step 2: Run; expect failures.
- [ ] Step 3: Migration `add_column :users, :team, :string`; `normalizes :team, with: ->(t) { t.strip.presence }`; `validates :team, length: { maximum: 30 }`; field `f.text_field :team, maxlength: 30, list: "team-suggestions"` + `datalist` built from `User.team_suggestions` (loaded in the controller `show`/`update` as `@team_suggestions`), hint under the field; permit; anonymize; copy (pt "Equipa", hint from the spec; es "Equipo" / "El grupo con el que pruebas y juegas. Aparece junto a tu nombre.").
- [ ] Step 4: `bin/rails test test/models test/controllers/accounts_controller_test.rb test/services test/i18n_parity_test.rb`; PASS.
- [ ] Step 5: Commit `feat(m12): team on the account`.

### Task 3: Profile view (server-rendered)

**Files:**
- Modify: `app/views/profiles/show.html.erb`, `app/views/profiles/_event_row.html.erb` (becomes the table row + detail row pair), `app/helpers/profiles_helper.rb` (`profile_percent`, `profile_cut_tag`, `profile_team_tag`, `profile_years(rows)`, `profile_seasons(rows)`), `app/controllers/profiles_controller.rb` (`@summary = Profiles::Summary.call(@history)`), `app/views/layouts/public.html.erb` (`wide_main`), `app/assets/tailwind/application.css` (`/* profile */` block), `config/locales/{en,pt,es}.yml` (spec §6 keys)
- Create: `app/views/profiles/_summary.html.erb`, `app/views/profiles/_toolbar.html.erb`
- Test: `test/controllers/profiles_controller_test.rb`, `test/views/profile_summary_test.rb` (create, ActionView::TestCase for the band with hand-built rows)

**Interfaces:**
- Consumes: `Profiles::History::Row` (Task 1), `Profiles::Summary` (Task 1), `User#team` (Task 2).
- Produces: the markup of spec §4 with the exact `data-*` attributes (`data-profile-summary`, `data-stat`, `data-ach`, `data-commanders`, `data-profile-tools`, `data-year`, `data-season`, `data-profile-events`, `th[data-sort]`, `tr[data-event]` + attributes, `tr[data-event-detail]`, `[data-sign]`, `[data-more]`) that Task 4's controller reads. The table shows ALL rows server-side (the controller hides beyond 6).

- [ ] Step 1: Failing controller tests on a profile with 3 finished events (one Top-4 cut reached, one 1v1, one plain): the band shows `3` events, `1` top cut, the computed win rate and `33%` conversion; the achievements box shows wins/top4/cuts; the commanders list has the decklist names; the toolbar has the search input, year buttons for the events' years and the season select with the circuit; the table has 3 `tr[data-event]` rows with the data attributes, the cut row has the tag "Top 4" after the name, the 1v1 detail says "1v1 · no seats", the result cell has no `text-accent`; the team tag appears when set and not when blank; `[data-profile-summary]` absent for a user without events. View test: the band renders "–" rates for zero games.
- [ ] Step 2: Run; expect failures.
- [ ] Step 3: Implement the views, helpers, CSS, copy and layout width.
- [ ] Step 4: `bin/rails test test/controllers/profiles_controller_test.rb test/views test/i18n_parity_test.rb`; PASS; forbidden-colour grep 0; rubocop.
- [ ] Step 5: Commit `feat(m12): profile band, toolbar and events table (server-rendered)`.

### Task 4: Stimulus `profile_events` controller, system test, docs

**Files:**
- Create: `app/javascript/controllers/profile_events_controller.js`, `test/system/player_profile_test.rb`
- Modify: `app/views/profiles/show.html.erb` (controller attributes/targets/actions only), `CLAUDE.md` (profile bullet), `docs/superpowers/notes/2026-11-04-backlog-after-m6.md` (M12 DONE line)

**Interfaces:**
- Consumes: the `data-*` contract from Task 3.
- Behaviour: `search` (input), `year` (click), `season` (change), `sort` (click on `th[data-sort]`; date desc default, name asc, position asc; clicking the active header flips), `toggle` (the "+", sets `hidden` on the detail row, `aria-expanded`, `[data-sign]` "+"/"–", `bg-ink text-ground` class pair), `more` (expand/collapse past 6). `render()` recomputes: count text, band numbers (events, top cuts, win rate, conversion, wins = position 1, top4 = position ≤ 4, cuts = `data-cut="1"`), commanders list (top 4 with count and percent and bar width), and hides rows past 6 unless expanded. Filtering collapses open details and resets "more".

- [ ] Step 1: Failing system test (`player_profile_test.rb`, Capybara): profile with 8 finished events over two years and two circuits; asserts 6 rows visible and "Show all 8 events"; click → 8 visible and "Show less"; type a commander → only its rows visible and the events stat equals that count; click a year → count text "n of 8 events"; choose a season; click "+" on a row → the detail row visible with "Record" and the per-round seats, the button shows "–"; search with no match → "No events match." and the rates show "–".
- [ ] Step 2: Run; expect failure (no controller).
- [ ] Step 3: Implement the controller (plain Stimulus, no dependencies, ~120 lines; numbers from `dataset`), wire targets/actions in the view; keep the server-rendered state as the no-JS fallback.
- [ ] Step 4: `bin/rails test:system test/system/player_profile_test.rb`, `bin/rails test`, rubocop, forbidden-colour grep. Update CLAUDE.md (profile section: band, filters, team) and the backlog note.
- [ ] Step 5: Commit `feat(m12): profile events filtering, sorting and details in the browser`.

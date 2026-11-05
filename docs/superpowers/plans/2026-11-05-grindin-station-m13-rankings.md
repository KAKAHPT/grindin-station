# M13 Rankings and Event Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One public `/rankings` page (ranking points, Elo leaderboard, team ranking) with shared filters, the same filters on `/events`, a per-event country, and an admin-only event tier feeding an invitational leaderboard.

**Architecture:** Two read-only tables rebuilt by a job: `ranking_contributions` (one row per player and finished event: games, cut flags, points, invitational points, snapshot of country/team/organizer/format/season) and `elo_ratings` (one row per player and season, plus all time). Pure calculators `Rankings::Points` and `Rankings::Elo` are unit-tested on their own; `Rankings::Rebuild` writes the tables; `Rankings::RebuildJob` runs nightly and after finishes/corrections with a debounce. Pages only read the tables through `Rankings::Board` with URL filters. `/events` reuses the filter bar markup over its existing scopes.

**Tech Stack:** Rails 8.1, PostgreSQL, Hotwire (one small Stimulus `dialog` controller), Tailwind 4, Minitest + Capybara, Solid Queue recurring, Prosopite.

**Spec:** `docs/superpowers/specs/2026-11-05-m13-rankings-and-event-filters.md` (mock: `public/mock/rankings.html`).

## Global Constraints

- Points (spec D4): per game win 3, draw 1, loss 0 (Penalty is a Loss), bye 1 (`Advance` in a `SwissRound`); bonuses: made cut +5, top 4 +5 more, won +10 more (tournaments only); field factor by non-waitlisted participants: ≤ 16 ×1, 17–32 ×1.25, 33–64 ×1.5, > 64 ×2; `points` decimal(8,2). Leagues: games only, factor from participants.
- Elo (spec D5): start 1500, K 32, `E = 1 / (1 + 10 ** ((rb - ra) / 400.0))`, `R' = R + K * (S - E)` applied per duel with both players' pre-duel ratings; pods = all pairs of seated players with a current Win/Draw/Loss result (winner 1 vs each, others 0 vs winner and 0.5 among themselves; all-Draw pod = 0.5 everywhere); byes/Advance skipped; 1v1 match = one duel. Order: event start_time, round number, pod number. Provisional under 10 rated games.
- Teams (spec D7): contribution = points + 15 × made_cut + 30 × won; team score = sum of the five best contributions; team snapshot from `users.team` at rebuild.
- Tiers (spec D16): `events.tier` string default "none", `Event::TIERS = %w[none bronze silver gold platinum]`, multipliers `{ "none" => 0, "bronze" => 1, "silver" => 1.5, "gold" => 2, "platinum" => 3 }`; `invitational_points = points × multiplier`; admin-only; audited `tier_changed`.
- Season = `event.start_time.year`; `elo_ratings.season` nil = all time.
- Filters in the URL: `season` (year or `all`), `country` (ISO-2), `organizer` (organizer user handle), `format` (`multiplayer` | `one_v_one`), `team` (exact), `q`, `tab` (`points` | `elo` | `teams`), `all=1` (show all rows). Unknown values are ignored (treated as unset), never raise.
- Grey only; accent only for a positive rating change, danger for a negative one; M7 pieces (`card`, `ctable`, `seg`, `.field`); the filter bar partial is shared by `/rankings` and `/events`. `grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0.
- Copy en/pt-PT/es with parity; only task files committed (`git commit -- <paths>`); rubocop clean; Prosopite clean (pages read only the two tables plus one users/players preload).
- Never compute points or Elo in a request; pages read `ranking_contributions` / `elo_ratings` only.

## Review Focus

1. A drawn pod must give every pair 0.5 and leave equal ratings unchanged (Task 2 test).
2. A player with a Penalty must get 0 for that game and the others in the pod scored as a loss for them, not a draw among themselves (Task 1/2 tests: penalty = loss).
3. `Rebuild` must be idempotent and must not double count a corrected result (uses `Result.current`) (Task 3 test: run twice, same rows; supersede a result, rerun, rows change).
4. `/rankings?country=PT` must not change anyone's rating, only the listing (Task 4 test).
5. `/events?country=XX` (unknown) must list every event, not none (Task 5 test).

---

### Task 1: Tables, country/tier columns, `Rankings::Points`, contributions builder

**Files:**
- Create: `db/migrate/<ts>_create_ranking_tables.rb` (both tables + `events.country` + `events.tier`), `app/models/ranking_contribution.rb`, `app/models/elo_rating.rb`, `app/services/rankings/points.rb`, `app/services/rankings/contributions.rb`
- Modify: `app/models/event.rb` (TIERS, TIER_MULTIPLIERS, `validates :tier, inclusion`, `validates :country, format: /\A[A-Z]{2}\z/, allow_nil`, `normalizes :country`)
- Test: `test/services/rankings/points_test.rb`, `test/services/rankings/contributions_test.rb`, `test/models/event_tier_test.rb`

**Interfaces:**
- Produces: `ranking_contributions` (uuid id, `player_id` uuid not null, `event_id` uuid not null, `season` integer not null, `country` string(2) null, `team` string null, `event_organizer_id` uuid null, `format` string not null, `field` integer not null, `wins` `draws` `losses` `byes` integer default 0, `made_cut` `top4` `won` boolean default false, `points` decimal(8,2) default 0, `invitational_points` decimal(8,2) default 0, timestamps; unique index on `[player_id, event_id]`, indexes on `season`, `country`, `event_organizer_id`, `team`). `elo_ratings` (`player_id`, `season` integer null, `rating` decimal(8,2) default 1500, `previous_rating` decimal(8,2) default 1500, `peak` decimal(8,2) default 1500, `games` integer default 0, `wins` integer default 0, timestamps; unique `[player_id, season]`).
- Produces: `Rankings::Points::FIELD_FACTORS = [[16, 1], [32, 1.25], [64, 1.5], [Float::INFINITY, 2]]`, `Rankings::Points.factor(field) -> Numeric`, `Rankings::Points.games(wins:, draws:, byes:) -> Integer` (3w + d + b), `Rankings::Points.bonuses(made_cut:, top4:, won:) -> Integer` (5, +5, +10 cumulative), `Rankings::Points.total(field:, wins:, draws:, byes:, made_cut:, top4:, won:, league: false) -> BigDecimal` (2 dp).
- Produces: `Rankings::Contributions.build(event) -> Array<Hash>` (one hash per non-waitlisted participant with a player, attribute names = the table columns, computed from the event's current results in a fixed number of queries: results with rounds, SE seatings for `made_cut`, `final_position` for `top4`/`won` (1 ≤ pos ≤ 4 / pos == 1, tournaments only), `field` = non-waitlisted count, `country`/`team` from `player.user`, `invitational_points` = points × `Event::TIER_MULTIPLIERS[event.tier]`).

- [ ] Step 1: Failing tests: `Points.total` for the spec acceptance cases: 16 players, 3 wins 1 draw, cut+top4+won → 30; same at 80 players → 60; 2-1-1 made cut only at 16 → 12; league 4 wins at 20 players → 15.0; bye counts 1; factor boundaries 16/17/32/33/64/65; Penalty counted as a loss in `Contributions.build` (0 points, `losses` 1); a 1v1 match win counts as one win; `Contributions.build` on a played 16-player event returns a hash per participant with `season`, `field`, flags and points matching `Points.total`; waitlisted and playerless participants are skipped; `Event` rejects `tier: "diamond"` and `country: "Portugal"`, normalises `"pt"` to `"PT"`.
- [ ] Step 2: Run; expect failures.
- [ ] Step 3: Migration, models, services. Run `bin/rails db:migrate` for dev and test.
- [ ] Step 4: `bin/rails test test/services/rankings test/models`; PASS.
- [ ] Step 5: Commit `feat(m13): ranking tables, event country and tier, points and contributions`.

### Task 2: `Rankings::Elo`

**Files:**
- Create: `app/services/rankings/elo.rb`, `app/services/rankings/duels.rb`
- Test: `test/services/rankings/elo_test.rb`, `test/services/rankings/duels_test.rb`

**Interfaces:**
- Produces: `Rankings::Elo.new(k: 32, start: 1500)`; `#rating(id) -> Float`; `#games(id)`, `#wins(id)`, `#peak(id)`; `#play(a, b, score_a)` updates both from their pre-duel ratings (score_a 1 / 0.5 / 0); `#provisional?(id)` = games < 10; `#to_h -> { id => { rating:, peak:, games:, wins: } }`.
- Produces: `Rankings::Duels.for_pod(pod) -> Array<[a_player_id, b_player_id, score_a]>` from the pod's seatings and current results (Win/Draw/Loss/Penalty; Advance and missing results skip that player); for a 1v1 pod one duel; `Rankings::Duels.for_event(event) -> Array` in round number then pod number order, Swiss and cut rounds alike, with the results and seatings preloaded (fixed queries).
- Consumes: `Pod#seatings`, `Pod#current_results`, `Result` classes.

- [ ] Step 1: Failing tests: worked example (Ana 1500 wins vs 1600/1500/1400 → 1548 ± 0.5, games 3); a drawn pod of equal ratings leaves all at 1500; expected score 1500 vs 1700 ≈ 0.24; provisional until 10 games; `Duels.for_pod` of a 4-player pod with one Win and three Losses gives 6 duels with the right scores; all-Draw pod gives six 0.5; a pod with a Penalty treats it as a loss; a dropped player without a result is skipped (3 duels among the rest); 1v1 pod gives one duel; `Duels.for_event` orders by round then pod.
- [ ] Step 2: Run; expect failures. Step 3: implement. Step 4: `bin/rails test test/services/rankings`; PASS.
- [ ] Step 5: Commit `feat(m13): Elo calculator and pod duels`.

### Task 3: `Rankings::Rebuild`, job, triggers, recurring

**Files:**
- Create: `app/services/rankings/rebuild.rb`, `app/jobs/rankings/rebuild_job.rb`, `lib/tasks/rankings.rake` (`rankings:rebuild`)
- Modify: `app/jobs/tournaments/finish_tournament_job.rb`, `app/jobs/leagues/finish_league_job.rb`, `app/services/results/apply.rb` (after the `result_corrected` audit), `config/recurring.yml` (05:00 daily)
- Test: `test/services/rankings/rebuild_test.rb`, `test/jobs/rankings/rebuild_job_test.rb`

**Interfaces:**
- Produces: `Rankings::Rebuild.call -> { contributions: Integer, ratings: Integer, at: Time }`: in one transaction deletes and reinserts `ranking_contributions` for every finished Tournament/League (`insert_all` in batches), then recomputes `elo_ratings` per season and for all time (`season: nil`) by feeding `Rankings::Duels.for_event` of each finished event in start_time order into `Rankings::Elo`; `previous_rating` = the rating stored before this rebuild (1500 for new rows); rows for players no longer present are deleted. `Rankings.last_rebuilt_at -> Time | nil` = `EloRating.maximum(:updated_at)`.
- Produces: `Rankings::RebuildJob.schedule!` enqueues `perform_later` with `wait: 5.minutes` unless `Rails.cache.write("rankings:rebuild:scheduled", true, unless_exist: true, expires_in: 5.minutes)` says one is pending; `perform` deletes the key and calls `Rebuild.call`.
- Consumes: Tasks 1–2.

- [ ] Step 1: Failing tests: `Rebuild.call` twice gives identical rows (compare attributes minus timestamps); superseding a Win by a Loss (`Results::Apply` or direct `superseded_by_id`) and rerunning changes the player's points and rating; a finished event with no results produces rows with zero points; `schedule!` enqueues once within 5 minutes (assert_enqueued_jobs 1 after two calls); `FinishTournamentJob` calls `schedule!`; `Results::Apply` correction path calls `schedule!`.
- [ ] Step 2: Run; expect failures. Step 3: implement; recurring entry `rankings_rebuild: class: Rankings::RebuildJob, schedule: every day at 5am`. Step 4: `bin/rails test test/services/rankings test/jobs`; PASS. Run `bin/rails rankings:rebuild` in dev and note the counts.
- [ ] Step 5: Commit `feat(m13): rankings rebuild job, triggers and nightly schedule`.

### Task 4: `/rankings` page

**Files:**
- Create: `app/queries/rankings/board.rb`, `app/controllers/rankings_controller.rb`, `app/views/rankings/show.html.erb`, `app/views/rankings/_points.html.erb`, `_elo.html.erb`, `_teams.html.erb`, `_how_points.html.erb`, `_how_elo.html.erb`, `_how_teams.html.erb`, `app/views/shared/_filter_bar.html.erb`, `app/views/shared/_filter_chips.html.erb`, `app/javascript/controllers/dialog_controller.js`, `app/helpers/rankings_helper.rb`
- Modify: `config/routes.rb` (`get "/rankings", to: "rankings#show", as: :rankings`), `app/views/shared/_topbar.html.erb` (Rankings → `rankings_path`), `app/views/circuits/index.html.erb` (unchanged page; the rankings footer links to it), `config/locales/{en,pt,es}.yml`, `app/assets/tailwind/application.css` (`/* rankings */` block: tabs, chips, strip)
- Test: `test/queries/rankings/board_test.rb`, `test/controllers/rankings_controller_test.rb`

**Interfaces:**
- Produces: `Rankings::Board.new(params) ` with `#filters` (normalised: season Integer or `:all`, country, organizer handle → `event_organizer_id`, format, team, q), `#seasons -> [Integer]` (years with contributions, desc), `#countries`, `#organizers -> [[name, handle]]`, `#teams`, `#points -> [Row]` (Row: player, user, points, events, wins, top_cuts, conversion, best), `#elo -> [Row]` (rating, change, peak, games, win_pct, provisional), `#teams_board -> [Row]` (team, points, avg_rating, players, events, wins, top_cuts), `#summary -> { players:, events:, organizers:, updated_at: }`. All from `ranking_contributions` + `elo_ratings` with one preload of players→users (avatar, handle, visibility, team, country). Points rows aggregate the filtered contributions with SQL `GROUP BY player_id`; Elo rows take the season rating of the players who have at least one matching contribution (country/team from the user when `season == :all`, else from contributions); teams rows aggregate contributions by `team` with the five-best rule in Ruby.
- Produces: `shared/_filter_bar` locals: `url:` (form action), `fields:` (ordered list of `[name, type, options, selected]` with types `:search`, `:segment`, `:select`), `count:`; renders a GET form (`data-turbo-frame="_top"`), the segment as links, selects with `onchange` submit via a tiny `data-action="change->form#submit"` (use `requestSubmit` through the `form` Stimulus controller if one exists, else add `submit_on_change_controller.js`). `shared/_filter_chips` locals: `chips: [[label, value, url_without]]`, `clear_url:`.
- Produces: `dialog_controller.js`: `open`/`close` on a `<dialog>`; Escape and backdrop close.
- Page: title, lead, tabs (links with `tab=`), filter bar, chips, summary strip, the tab's table (20 rows unless `all=1`, "Show all N" link), the note with the "How…" button opening the tab's `<dialog>` (copy from the mock, in the three locales), footer line linking `/circuits`.

- [ ] Step 1: Failing tests: `Board` with a fixture set (players in PT/ES, two organizers, both formats, two teams, two seasons, contributions built via `Rankings::Rebuild` on `TournamentBuilder` events) → points rows ordered by points, filtered by each param, unknown values ignored; Elo rows unchanged by `country` (same rating, fewer rows); teams five-best rule; summary counts. Controller: `/rankings` 200 with the three tabs, bar, chips for active params, strip, 20 rows then "Show all"; `tab=elo` shows the rating columns and provisional marks; `tab=teams`; hidden-profile player shows name without link; the three dialogs present with both sections; Prosopite query budget ≤ 10.
- [ ] Step 2: Run; expect failures. Step 3: implement. Step 4: `bin/rails test test/queries test/controllers/rankings_controller_test.rb test/i18n_parity_test.rb`; colour grep 0; rubocop.
- [ ] Step 5: Commit `feat(m13): /rankings with points, Elo and teams tabs, filters and explanations`.

### Task 5: Event country field and `/events` filters

**Files:**
- Modify: `app/views/organizer/tournaments/_form.html.erb` and `app/views/organizer/leagues/_form.html.erb` (Country field after Address, `maxlength: 2`, uppercase, hint), the two organizer controllers' permitted params, `app/models/event.rb` (`before_validation` default country from `event_organizer.user&.country` on create when blank), `app/controllers/events_controller.rb` + `app/controllers/concerns/event_tickets.rb` (`ticket_scope` takes `filters:`), `app/views/events/index.html.erb` (filter bar + chips under the list header), `config/locales/*`
- Test: `test/controllers/events_controller_test.rb` (create), `test/controllers/organizer/tournaments_controller_test.rb`, `test/models/event_tier_test.rb` (country default)

**Interfaces:**
- Produces: `EventTickets#ticket_filters -> Hash` from params (`season`, `country`, `organizer` handle, `format`, `q`); `ticket_scope(klass, past:, except:, filters:)` applies `where(country:)`, `where(format:)`, `where(event_organizer_id:)` (handle → organizer via `User.find_by(handle:)&.event_organizer`), `where("EXTRACT(YEAR FROM start_time) = ?", season)`, and `q` over `name ILIKE`, `address ILIKE`, organizer user name ILIKE (join). Options for the bar from the visible events (years, countries, organizers) in one query each.
- Consumes: `shared/_filter_bar`, `shared/_filter_chips` (Task 4).

- [ ] Step 1: Failing tests: creating a tournament without a country takes the organizer's; the Settings form shows and saves `country`; `/events?country=PT` lists only PT events, `country=XX` lists all, `organizer=<handle>` only theirs, `season=2025`, `format=one_v_one`, `q=porto` by name or address; chips and "Clear all" present; pagination keeps the filters (`page=2` link carries params).
- [ ] Step 2: Run; expect failures. Step 3: implement. Step 4: tests + rubocop + colour grep.
- [ ] Step 5: Commit `feat(m13): event country and filters on /events`.

### Task 6: Admin tier and invitational leaderboard

**Files:**
- Modify: `app/controllers/admin/events_controller.rb` (`tier` action: `PATCH /admin/events/:id/tier` with `tier` param validated against `Event::TIERS`, `update_columns`, audit `tier_changed` with old/new), `config/routes.rb`, `app/views/admin/events/index.html.erb` (tier select per row submitting on change), `app/models/audit_event.rb` (`tier_changed`), `app/views/admin/_nav.html.erb` (Invitational tab), `config/locales/*`
- Create: `app/controllers/admin/invitational_controller.rb` (`show` with `season`; `export` CSV), `app/views/admin/invitational/show.html.erb`, `app/services/exports/invitational.rb`
- Test: `test/controllers/admin/events_controller_test.rb`, `test/controllers/admin/invitational_controller_test.rb`, `test/services/exports/invitational_test.rb`

**Interfaces:**
- Produces: `Exports::Invitational.call(season:) -> String` CSV (`standing,name,handle,email,invitational_points,tier_events,points,events`) via `Exports::CsvFile.generate` (safe cells); audited `data_exported` kind `invitational`.
- Page: season segmented control, table (#, player, invitational points, tier events, ranking points, events), export link; 404 for non-admins (inherits `Admin::BaseController`).
- `/admin/events` gets a filter form in the Audit page's style (read app/views/admin/audit/index.html.erb and its controller for the pattern): `q` (name or slug ILIKE, or the organizer user's name/e-mail), `state`, `format`, `tier`, `organizer` (handle); filters survive pagination and the tier PATCH redirect (pass them through like `page`).

- [ ] Step 1: Failing tests: `/admin/events?q=porto&state=finished&tier=gold&format=multiplayer` narrows the rows and keeps the filters in the pagination links and after a tier change; PATCH tier gold persists, audits, rejects `diamond` (422/redirect with alert, unchanged); after `Rankings::Rebuild.call` a gold event's players have `invitational_points == points × 2`, none for `none`; `/admin/invitational` lists them ordered, filtered by season; export CSV headers and a row; non-admin 404; `/rankings` and `/t/:slug` contain no tier text.
- [ ] Step 2: Run; expect failures. Step 3: implement. Step 4: tests + rubocop.
- [ ] Step 5: Commit `feat(m13): admin event tiers and the invitational leaderboard`.

### Task 7: Admin organizers tab (waiting-list approvals)

**Files:**
- Create: `db/migrate/<ts>_add_review_to_waitlist_signups.rb` (`approved_at` datetime, `approved_by_id` uuid, `declined_at` datetime), `app/controllers/admin/organizers_controller.rb` (`index` with `filter` pending|approved|declined and `q` on name/e-mail for both the signups and the organizers list, in the Audit page's filter style; `approve`, `decline`, `revoke`), `app/views/admin/organizers/index.html.erb`, `app/mailers/organizers_mailer.rb` + `app/views/organizers_mailer/approved.{html,text}.erb`
- Modify: `app/models/waitlist_signup.rb` (scopes `pending`/`approved`/`declined`, `#user -> User | nil` by e-mail, `#approvable?`), `app/models/audit_event.rb` (`organizer_approved organizer_declined organizer_revoked`), `app/views/admin/_nav.html.erb` (Organizers tab), `config/routes.rb` (`resources :organizers, only: :index { member { patch :approve; patch :decline } }` + `patch "organizers/:id/revoke"` on the organizer id), `config/locales/*`
- Test: `test/controllers/admin/organizers_controller_test.rb`, `test/mailers/organizers_mailer_test.rb`

- [ ] Step 1: Failing tests per spec acceptance 10 (approve with account → organizer created, stamps, audit, mail delivered; approve without account → 422/alert, no organizer; decline; revoke refused with events, allowed without; non-admin 404; filters).
- [ ] Step 2: Run; expect failures. Step 3: implement (M7 pieces: `ctable`, `desk_chip` for the status, `button_classes(:secondary, size: :sm)`; the Approve button `:light`). Step 4: tests + rubocop + i18n parity.
- [ ] Step 5: Commit `feat(m13): admin organizers tab with waiting-list approvals`.

### Task 9: One entry per player and event

**Files:**
- Create: `db/migrate/<ts>_add_unique_player_per_event.rb` (removes exact duplicates keeping the oldest row, then `add_index :event_participants, [:event_id, :player_id], unique: true, where: "player_id IS NOT NULL"`)
- Modify: `app/models/event_participant.rb` (`validates :player_id, uniqueness: { scope: :event_id }, allow_nil: true`, error key `taken_in_event`), `config/locales/{en,pt,es}.yml` (activerecord error message "is already in this event" / "já está neste evento" / "ya está en este evento"), `app/services/registrations/enroll.rb` (raise `Registrations::Enroll::AlreadyEnrolled` before creating when `event.event_participants.exists?(player:)`; callers that rescue `Full`/`Closed` also rescue it with a flash — grep them)
- Test: `test/models/event_participant_test.rb` (or the closest existing model test), `test/controllers/organizer/event_participants_controller_test.rb`, `test/services/registrations/enroll_test.rb`

- [ ] Step 1: Failing tests: a second `EventParticipant` for the same player and event is invalid with the message; the organizer add-participant form with an e-mail already in the event re-renders 422 with the error; `Enroll.call` twice raises `AlreadyEnrolled`; the migration index exists (schema).
- [ ] Step 2: Run; expect failures. Step 3: implement. Step 4: `bin/rails test test/models test/controllers/organizer/event_participants_controller_test.rb test/services/registrations test/i18n_parity_test.rb`; rubocop.
- [ ] Step 5: Commit `feat(m13): one entry per player and event`.

### Task 8: System test, docs

**Files:**
- Create: `test/system/rankings_test.rb`
- Modify: `CLAUDE.md` (Rankings section: tables, points, Elo, teams, tiers, filters, rebuild job/task; Admin: organizers tab), `docs/superpowers/notes/2026-11-04-backlog-after-m6.md` (M13 DONE)

- [ ] Step 1: System test: `/rankings` tab switching, a filter via the bar updates the URL and the table, chips ✕ removes one filter, each "How…" dialog opens and closes (✕, Escape); `/events` filter by country; `/admin/organizers` approve flow.
- [ ] Step 2: `bin/rails test`, `bin/rails test:system`, rubocop, colour grep, `bin/rails rankings:rebuild`.
- [ ] Step 3: Commit `docs(m13): rankings and admin organizers in CLAUDE.md and the backlog; system test`.

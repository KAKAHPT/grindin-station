# League Open Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Players of a running league open and join tables of four on the league page; a full table becomes a pod that counts for the league's wager standings; the organizer runs start, close, cancellations, cut and finish from the site.

**Architecture:** A waiting table is its own record (`LeagueTable` + `LeagueTableSeat`). When the 4th player joins, one `LeagueGameRound` (a new `Round` subclass that never auto-pairs) is created with a single `Pod`, so `Results::Report/Confirm/Contest/Apply` work unchanged (results are unique per round and participant, so one round per game). The cut uses a `LeagueCutRound < SingleEliminationRound` and a league subclass of the tournament cut job. Every league-only behaviour hangs off `League`, the two new round classes, or an `is_a?(League)` guard; no tournament code path changes.

**Tech Stack:** Rails 8.1, PostgreSQL, Hotwire/Turbo, Tailwind 4, Solid Queue, Minitest + Capybara.

**Spec:** `docs/superpowers/specs/2026-11-25-league-open-tables-design.md`

## Global Constraints

- Shell setup before any `bin/rails`: `export PATH=/opt/homebrew/bin:$PATH && eval "$(mise activate bash)" 2>/dev/null`.
- `leagues: false` stays in `config/features.yml` (`shared`). Every new route goes inside `constraints(Features.constraint(:leagues))`; `test/integration/launch_phase_test.rb` must list the new paths as 404.
- No existing test under `test/` for tournaments may be edited to pass. `bin/rails test` and `bin/rails test:system` green.
- Green before every commit: `bin/rubocop`, `bundle exec herb analyze`, `bin/rails test test/i18n_parity_test.rb` (every key in en, pt, es).
- Prosopite raises on N+1 in tests: preload in controllers.
- Design: existing tokens and helpers only (`card`, `card-title`, `ctable`, `seg`, `tab`, `button_classes`, `desk_chip`); no emoji, no `gray-`/`dark:`/purple classes.
- Enum integers already stored never move. `events.play_mode` column default stays 0.
- Exact values: table size **4**; waiting timeout **2 hours** from opening; league result confirmation **"one"**, window **1440 minutes**, auto-accept on expiry; stale table notice after **7 days**; `starting_points` default **1000**; `min_games_for_cut` default **10**; `top_cut_size` default **16** (allowed 0, 4, 16); `draw_rule` `split` (default) | `lost`.
- Commit messages end with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

## Review Focus

1. Two players take the last seat at once → exactly one pod with 4 seatings; the loser gets `Leagues::Tables::NotAllowed("full")`. (Task 2)
2. A player with a pending cancellation or an unreported pod opens a second table → refused `busy`. (Task 2, 5)
3. A result corrected by the organizer after later games were played → every score recomputed from `starting_points`, in `finished_at` order. (Task 3)
4. A draw with `lost` and unequal scores → each loses their own stake, the total drops by the pot. (Task 3)
5. A league in `closing` whose last pod is cancelled (not reported) → moves to `closed` all the same. (Task 6)

---

### Task 1: Schema and league settings

**Files:**
- Create: `db/migrate/<ts>_add_league_open_tables.rb`, `app/models/league_table.rb`, `app/models/league_table_seat.rb`, `app/models/league_game_round.rb`, `app/models/league_cut_round.rb`
- Modify: `app/models/league.rb`, `app/models/pod.rb` (one `has_one :league_table`), `test/models/league_test.rb`

**Interfaces — Produces:**
- `events`: `starting_points:integer default 1000 null false`, `draw_rule:string default "split" null false`, `min_games_for_cut:integer default 10 null false`, `max_games_per_week:integer`, `max_games_vs_same_opponent:integer`.
- `pods`: `clock_started_at:datetime`.
- `league_tables` (uuid): `event_id` fk, `opener_id` fk event_participants, `state:string default "waiting"` (`waiting filled closed expired cancelled`), `pod_id` fk nullable (on delete nullify), `filled_at`, `stale_notified_at`, `cancel_reason:text`, `cancel_requested_by_id` fk event_participants nullable, `cancel_requested_at`, `cancel_state:string` (`pending approved refused`), `cancel_decided_by_id` fk users nullable, `cancel_decided_at`, timestamps. Index `[event_id, state]`.
- `league_table_seats` (uuid): `league_table_id`, `event_participant_id`, `active:boolean default true`, timestamps; unique `[league_table_id, event_participant_id]`; partial unique on `event_participant_id WHERE active` (one live table per player).
- `League`: `enum :play_mode, { scheduled: 0, pickup: 1, open_tables: 2 }`; `after_initialize` sets `play_mode: :open_tables`, `result_confirmation: "one"`, `confirmation_timeout_minutes: 1440`, `top_cut_size: 16` on `new_record?` when not given; states add `closing: 7, closed: 8`; `TRANSITIONS`: `registration_closed → play`, `registration_open → play` (registration stays open: see `accepts_registrations?`), `play → closing canceled`, `closing → closed play`, `closed → finals finished play`, `finals → finished`; `playing?` true for `play closing closed finals`; `TABLE_SIZE = 4`; `TABLE_WAIT = 2.hours`; `DRAW_RULES = %w[split lost]`; `CUT_SIZES = [0, 4, 16]`; validations (inclusion, non-negative integers, `starting_points >= 1`); `has_many :league_tables, foreign_key: :event_id, dependent: :destroy`; `tables_open?` = `play? && play_mode_open_tables? && end_time.future?`.
- `LeagueGameRound < Round`: `create_pods` no-op, `display_name` → `I18n.t("leagues.game", n: number)`, `duration` → `event.round_minutes.minutes`.
- `LeagueCutRound < SingleEliminationRound`: body in Task 7 (empty subclass here so STI loads).
- `LeagueTable`: `belongs_to :league, foreign_key: :event_id`, `belongs_to :opener`, `belongs_to :pod, optional: true`, `has_many :seats`, `has_many :participants, through: :seats`; scopes `waiting`, `filled`, `in_play` (filled, pod without results for every seat), `expires_at` = `created_at + League::TABLE_WAIT`, `expired?`.

- [ ] Write `test/models/league_test.rb` cases: `new league defaults to open tables, one confirmation, 1440 minutes, cut 16`; `closing and closed keep integers 7 and 8`; `draw_rule outside the list is invalid`; `a participant cannot hold two active seats` (expects `ActiveRecord::RecordNotUnique`).
- [ ] Run `bin/rails test test/models/league_test.rb` → fails (missing columns/classes).
- [ ] Write the migration and models; `bin/rails db:migrate`.
- [ ] Run again → pass; `bin/rails test test/models` → pass.
- [ ] Commit `feat(leagues): schema and settings for open tables`.

### Task 2: Table lifecycle

**Files:**
- Create: `app/services/leagues/tables/{not_allowed,open,join,leave,close,fill,expire}.rb`, `app/services/leagues/seat_counts.rb`, `app/jobs/leagues/expire_tables_job.rb`, `test/services/leagues/tables_test.rb`
- Modify: `config/recurring.yml` (`leagues_expire_tables`, every minute)

**Interfaces — Produces:**
- `Leagues::Tables::NotAllowed < StandardError` with message keys `not_enrolled closed busy limit_week limit_opponent full not_member not_opener not_waiting`.
- `Leagues::Tables::Open.call(league:, participant:) → LeagueTable` (seats the opener).
- `Leagues::Tables::Join.call(table:, participant:) → LeagueTable` (calls `Fill` on the 4th seat).
- `Leagues::Tables::Leave.call(table:, participant:)` (opener refused `not_opener`… the opener uses Close).
- `Leagues::Tables::Close.call(table:, participant:)` (opener only; state `closed`, seats `active: false`).
- `Leagues::Tables::Expire.call(now: Time.current) → Integer` (waiting tables older than `TABLE_WAIT` → `expired`).
- `Leagues::Tables::Fill.call(table:) → Pod`: creates `LeagueGameRound(number: league.rounds.maximum(:number).to_i + 1, is_play_round: true, published: true, started_at: now)`, one `Pod(number: 1, size: 4)`, seatings ordered by `Tournaments::SeatAssigner` over `Leagues::SeatCounts.for(league, ids)`, `assigned_by: "fair"`; table `filled`, `pod`, `filled_at`; `Notify.participants(pod, kind: "league_table_full", subject: pod)`.
- `Leagues::SeatCounts.for(league, participant_ids) → { id => { 1=>n, .., 5=>n } }` over `LeagueGameRound` seatings.
- Guards shared by Open/Join (private module `Leagues::Tables::Guard`): league `tables_open?` else `closed`; participant `enrolled?` else `not_enrolled`; `participant.lock!` then no active seat (`busy`); week limit counts the participant's filled tables with `filled_at >= 7.days.ago`; opponent limit (Join only) counts filled tables shared with each seated member.
- A seat stays `active` after filling and is released by `Leagues::SettlePod` (Task 3) or an approved cancellation (Task 5).

- [ ] Tests in `test/services/leagues/tables_test.rb`: `open seats the opener`; `second open while seated is refused busy`; `join third keeps waiting`; `join fourth creates one game round, one pod, four seatings ordered 1..4 and notifies the four`; `fifth join is refused full`; `two concurrent joins for the last seat yield one pod` (two threads, own connections); `leave frees the player`; `close by a non-opener is refused`; `close frees everyone`; `expire closes a 2h01 table and leaves a 1h59 one`; `join an expired table is refused not_waiting even before the job ran`; `week limit and opponent limit refuse`; `league not in play or past end_time refuses closed`.
- [ ] Run → fail. Implement. Run → pass.
- [ ] Commit `feat(leagues): players open, join, leave and close tables`.

### Task 3: Wager scoring and settling a pod

**Files:**
- Modify: `app/services/scoring/point_wager.rb` (rewrite), `app/services/results/apply.rb` (after `Standings::Snapshot.refresh`: `Leagues::SettlePod.call(@pod) if @round.is_a?(LeagueGameRound)`), `app/jobs/events/submit_result_job.rb` (drop `recalculate_league_scores`), `test/services/scoring/*`
- Create: `app/services/leagues/settle_pod.rb`, `test/services/leagues/settle_pod_test.rb`

**Interfaces — Produces:**
- `Scoring::PointWager.new(league).recalculate_all!`: every enrolled-or-dropped participant starts at `league.starting_points`; one pass over `LeagueGameRound`s with `finished_at`, ordered by `finished_at, number`; stake = `(score * wager_percentage / 100).round(2)` (nil percentage = 0); one `Win` → winner gets the pot; all `Draw` + `split` → each gets `pot / seats`; all `Draw` + `lost` → nobody gets the pot; any other mix (a `Penalty` seat counts as a loser) → winner takes the pot if exactly one `Win`, else treated as a draw. Writes `league_score` with `update_all`-style single statements per participant only when changed.
- `Leagues::SettlePod.call(pod)`: if `pod.finished?` and the round has no `finished_at`, set it (`update_columns`, no callbacks); release the four seats (`active: false`); `PointWager#recalculate_all!`; `Leagues::Lifecycle.settle_closing(league)` (Task 6; `respond_to?`-free: defined in Task 6, stub the constant with a no-op in this task).

- [ ] Tests: `winner takes four stakes` (1000, 10% → 1300/900/900/900); `split draw with unequal scores`; `lost draw drops the total by the pot`; `correcting the first game recomputes the later one`; `order follows finished_at, not round number`; `a late player starts at starting_points`; `settling releases the seats and stamps finished_at`; `player report + one confirmation updates league_score` (through `Results::Report` and `Results::Confirm`).
- [ ] Run → fail. Implement. Run → pass; `bin/rails test test/services/results test/jobs/events` → pass unchanged.
- [ ] Commit `feat(leagues): chronological wager scoring, settled on every final result`.

### Task 4: League confirmation window and stale tables

**Files:**
- Create: `app/services/results/accept_pending.rb`, `app/jobs/leagues/accept_pending_job.rb`, `app/jobs/leagues/flag_stale_tables_job.rb`, tests under `test/jobs/leagues/`
- Modify: `app/jobs/results/expire_pending_job.rb` (add `.where.not(events: { type: "League" })`), `config/recurring.yml` (`leagues_accept_pending` every 5 minutes, `leagues_flag_stale_tables` every day at 6am)

**Interfaces — Produces:**
- `Results::AcceptPending.call(pod:)`: applies `pod.pending_result` like `Results::Confirm#apply!` (locks the pod; no-op if nothing pending, finished or disputed).
- `Leagues::AcceptPendingJob#perform`: league pods with a pending result, not disputed, `reported_at` older than the event's `confirmation_timeout_minutes`.
- `Leagues::FlagStaleTablesJob#perform`: filled tables, `filled_at < 7.days.ago`, pod not finished, `stale_notified_at` nil → `Notify.staff(league, kind: "league_table_stale", subject: pod)` and stamp.

- [ ] Tests: `a league report older than 24 h is accepted and scored`; `23 h is left pending`; `a disputed pod is never accepted`; `tournament pods still go to review, league pods do not` (ExpirePendingJob); `a table filled 8 days ago notifies staff once`.
- [ ] Run → fail. Implement. Run → pass. Commit `feat(leagues): 24 h auto-accept and 7-day stale notice`.

### Task 5: Cancellation requests

**Files:**
- Create: `app/services/leagues/tables/{request_cancel,decide_cancel}.rb`, `test/services/leagues/cancel_test.rb`

**Interfaces — Produces:**
- `RequestCancel.call(table:, participant:, reason:)`: table `filled`, pod not finished, participant seated (`not_member`), reason present (`reason_required`), no pending request (`already_requested`); sets the `cancel_*` request fields, `cancel_state: "pending"`; `Notify.staff(league, kind: "league_cancel_requested", subject: table.pod)`.
- `DecideCancel.call(table:, by:, approve:)`: approve → destroy the game round (pod, seatings, results), table `cancelled`, seats released, `PointWager` recalculated, `Lifecycle.settle_closing`; refuse → `cancel_state: "refused"`, table stays `filled`. Both stamp `cancel_decided_*`, audit `league_table_cancel_decided`, and notify the four (`league_cancel_approved` / `league_cancel_refused`, subject the league).
- While `cancel_state == "pending"`: `Results::Report` still allowed (a confirmed result voids the request: `SettlePod` sets `cancel_state: "refused"` if pending).

- [ ] Tests: `blank reason refused`; `request locks nothing new but keeps the four busy`; `approve removes the pod, frees the four, scores unchanged`; `refuse keeps the pod`; `second request while pending refused`; `request by an outsider refused`.
- [ ] Run → fail. Implement. Run → pass. Commit `feat(leagues): cancel a table with the organizer's decision`.

### Task 6: League lifecycle

**Files:**
- Create: `app/services/leagues/lifecycle.rb`, `test/services/leagues/lifecycle_test.rb`
- Modify: `app/models/league.rb` (`perform_state_based_actions`), `app/controllers/organizer/leagues_controller.rb` (`transition`, permit new settings), `config/routes.rb` (`patch :transition, on: :member` inside the leagues constraint)

**Interfaces — Produces:**
- `Leagues::Lifecycle.start(league, by:)` (→ `play`), `.close(league, by:)` (→ `closing`; waiting tables → `closed`, seats released; then `settle_closing`), `.settle_closing(league)` (`closing` with no filled-unfinished table → `closed`), `.reopen(league, by:)` (`closing|closed` → `play`; refused once a `LeagueCutRound` exists), `.finish(league, by:)` (`closed` with `top_cut_size` 0, or after the cut → `finished`). Each audits `event_state_changed`.
- `PATCH /organizer/leagues/:id/transition?to=play|closing|reopen|finals|finished`.
- `League#perform_state_based_actions`: only `finished` → `Leagues::FinishLeagueJob`; the old `StartPlayRoundJob`/`StartFinalsRoundJob` calls are removed for `open_tables` leagues (kept for `pickup`).

- [ ] Tests: `close voids waiting tables and keeps filled ones`; `closing becomes closed when the last pod is reported`; `closing becomes closed when the last pod is cancelled`; `close with nothing in play goes straight to closed`; `reopen from closed returns to play`; `reopen after the cut started is refused`; `past end_time no table opens but the state stays play`; `extending end_time reopens table opening`.
- [ ] Run → fail. Implement. Run → pass. Commit `feat(leagues): start, close, reopen`.

### Task 7: Cut and finish

**Files:**
- Modify: `app/models/league_cut_round.rb`, `app/models/league.rb` (`rounds_info`, `cut_size_for_field`, `cut_field`, `number_of_swiss_rounds` → 0-safe helpers used by round pages), `app/jobs/leagues/finish_league_job.rb`
- Create: `app/jobs/leagues/create_cut_pods_job.rb` (`< Tournaments::CreateSingleEliminationPodsJob`), `test/jobs/leagues/cut_test.rb`

**Interfaces — Produces:**
- `League#cut_field → [EventParticipant]`: enrolled, at least `min_games_for_cut` settled league games, ordered by `league_score desc, wins desc, games asc, created_at asc`.
- `League#cut_size_for_field → 16 | 4 | 0`: the largest of `[top_cut_size, 4]` allowed sizes with `cut_field.size >= size`, else 0.
- `Leagues::Lifecycle.make_cut(league, by:)`: `closed` → `finals`; creates `LeagueCutRound(number: next, is_finals_round: true)`; with size 0 calls `finish` instead.
- `LeagueCutRound`: `create_pods` → `Leagues::CreateCutPodsJob`; `stage_index` = earlier cut rounds of the league; `last_single_elimination_round?` = `stage_index == stages.size - 1`; `advance_tournament!` → next `LeagueCutRound` or `event.update!(state: :finished)` + state actions; `display_name` → `t("leagues.cut_round.semi" | "final")`.
- `Leagues::CreateCutPodsJob`: overrides the player source (`league.cut_field.first(size)`; everyone else gets `Eliminated` in the first cut round) and `number_of_pods` (`stages[stage_index][:pods]`).
- `Leagues::FinishLeagueJob`: writes `final_position` 1..N (final's `Advance`, then finalists by league order, then semi-finalists, then the rest by `cut_field`-style order including non-qualified), then circuit points and `Rankings::RebuildJob.schedule!` as today.

- [ ] Tests: `players under min games are not in the cut`; `20 qualified → 16 in four pods, seeded 1-8-9-16 style by SpreadMatcher`; `9 qualified with size 16 → cut of 4`; `3 qualified → no cut, finish by standings`; `cut results do not change league_score`; `closing the final finishes the league and writes positions 1..N`; `min_games_for_cut 0 qualifies everyone`.
- [ ] Run → fail. Implement. Run → pass; `bin/rails test test/jobs/tournaments test/system/close_round_and_cut_test.rb` unchanged and green.
- [ ] Commit `feat(leagues): top cut with minimum games, final positions`.

### Task 8: Player pages

**Files:**
- Create: `app/controllers/play/league_tables_controller.rb`, `app/controllers/play/pod_clocks_controller.rb`, `app/views/play/league_tables/{index,_table,_my_pod}.html.erb`, `app/views/my_events/_league_pod.html.erb`, `test/controllers/play/league_tables_controller_test.rb`, `test/system/league_tables_test.rb`
- Modify: `config/routes.rb`, `app/controllers/play/base_controller.rb` (`current_pod` for a `League`: the participant's unfinished game pod, else their pod in the latest published cut round), `app/views/leagues/show.html.erb` (tabs: About · Tables · Standings), `app/views/my_events/index.html.erb`, `app/controllers/my_events_controller.rb` (preload), `config/locales/{en,pt,es}.yml`

**Interfaces — Produces (inside the leagues constraint, under `/t/:slug`):**
- `GET league_tables` (public read), `POST league_tables`, `POST league_tables/:id/join|leave|close`, `POST pods/:pod_id/cancellation` (`reason`), `POST pods/:pod_id/clock`.
- `rescue_from Leagues::Tables::NotAllowed` → redirect back with `t("leagues.tables.not_allowed.<key>")`.
- Live: `LeagueTable` `after_commit` broadcasts a Turbo refresh to `[league, :tables]`.
- Report / confirm / contest keep the existing `/t/:slug/pods/:pod_id/report…` routes.
- Views: Tables tab shows "Open a table" (or the reason it is disabled), My table pinned, waiting tables oldest first (names link to profiles, seats left, minutes left), In play. `/my-events`: under a running league, the current pod with Submit result, Cancel table (dialog, required textarea), Open clock, or a link to the Tables tab.

- [ ] Controller tests: visitor sees tables and no buttons; enrolled player opens, another joins, leaves; every `NotAllowed` key renders its message; cancellation without a reason is refused; clock sets `clock_started_at` once.
- [ ] System test (phone size, restore the size afterwards): four players fill a table, one reports, one confirms, standings show 1300/900/900/900.
- [ ] Run → fail. Implement. Run → pass; `bin/rails test test/controllers/play test/system/player_report_flow_test.rb` unchanged and green.
- [ ] Commit `feat(leagues): tables tab, my pod, clock`.

### Task 9: Organizer pages

**Files:**
- Modify: `app/views/organizer/leagues/{_form,show,new,edit}.html.erb`, `app/controllers/organizer/leagues_controller.rb`, `config/routes.rb`, locales
- Create: `app/controllers/organizer/league_tables_controller.rb` (`index`, `approve`, `refuse`), `app/views/organizer/league_tables/index.html.erb`, `test/controllers/organizer/league_tables_controller_test.rb`, `test/system/league_lifecycle_test.rb`

**Interfaces — Produces:**
- Form in the tournament form's style, translated: name, cover, dates, min/max players, mode (`open_tables` default, `pickup`), starting points, wager %, draw rule, cut size (16 / 4 / none), minimum games for the cut, the two optional limits, circuit, prizes, description, price. Scoring settings lock once the league is in play.
- Show page: state buttons per `League#transitions` (Start league, Close league, Reopen, Make cut, Finish), "N tables still to finish" with links to each pod's organizer page, cancellation requests with reason and Approve / Refuse, stale flag.
- `GET /organizer/leagues/:id/tables`, `PATCH …/tables/:id/approve|refuse`.

- [ ] Controller tests: only the league's organizer; approve/refuse call `DecideCancel`; settings locked in play.
- [ ] System test: organizer starts, players play one table, organizer closes, makes the cut (field of 4), reports the final, league finished with positions.
- [ ] Run → fail. Implement. Run → pass. Commit `feat(leagues): organizer form, state buttons, cancellations`.

### Task 10: Launch gate, docs, full run

**Files:** `test/integration/launch_phase_test.rb`, `test/integration/authorization_sweep_test.rb`, `CLAUDE.md` (League section), `config/features.yml` (comment only)

- [ ] Add every new path to the launch-phase 404 list and the authorization sweep.
- [ ] Rewrite CLAUDE.md "League State Machine" and "League Scores" for the new behaviour.
- [ ] Run `bin/rubocop && bundle exec herb analyze && bin/rails test && bin/rails test:system` → all green.
- [ ] Commit `docs(leagues): open tables mode`.

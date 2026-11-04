# Grindin Station M6 — event formats (1v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An organiser picks the event format at creation: `multiplayer` (today, unchanged) or `one_v_one` (tables of two, best-of-3/best-of-1 with game scores, MTR Swiss pairing, MTR tiebreakers, MTR bracket and rounds table).

**Architecture:** Format is a column on `events`; every format-specific behaviour branches once at a seam that already exists: `CreatePodsJob` (pairer), `CreateSingleEliminationPodsJob` (bracket), `EventParticipant#rank_score`/`standing_columns` (tiebreakers), `Tournaments::Structure`/`TopCut` (suggestions and cut sizes), `Results::Apply` (game scores), and format-aware partials. Multiplayer code paths are not edited except to add the branch.

**Tech Stack:** Rails 8.1, PostgreSQL, Hotwire/Stimulus, Minitest + Capybara.

**Spec:** `docs/superpowers/specs/2026-11-04-1v1-format-design.md` (binding). Research: `docs/superpowers/notes/2026-11-04-1v1-formats-research.md`.

## Global Constraints

- Multiplayer behaviour byte-for-byte unchanged: `bin/rails "grindin:simulate[500]"` must still pass; existing tests must not be rewritten to accommodate 1v1 (only extended).
- Integer arithmetic in `rank_score`; percentages × 10 000 rounded; floors at 0.33 (MTR).
- Copy in `config/locales/{en,pt}.yml`; Prosopite raises on N+1 in tests; frozen string literals, double quotes, `params.expect`; `bin/rubocop` clean.
- Never run the test suite in two checkouts at once.

## Review Focus

1. A 1v1 event with an odd field must give exactly one bye per round, never to the same player twice while another never had one, and the bye must count 3 match points, 6 game points and be excluded from OMW/OGW (Tasks 2 and 4 tests).
2. Rematches must not happen in 1v1 Swiss while any rematch-free pairing exists (Task 4 test over 5 rounds of 16 with the seed fixed).
3. A multiplayer event must produce identical pods, seats and standings before and after this plan (Task 7 runs the full suite and the simulation; Task 1 asserts `format` default).
4. The organizer and the player must not be able to enter an impossible score (2-2, 3-0 in bo3, 2-0 in bo1): validated in `Results::Apply` (Task 5 test).
5. A 1v1 bracket must pair 1v8, 2v7, 3v6, 4v5 and then 1/8-winner vs 4/5-winner (Task 4 test with upsets).

---

### Task 1: Schema, format and game-score columns

**Files:**
- Create: `db/migrate/*_add_format_to_events.rb` (`events.format` string null:false default "multiplayer"; `events.match_games` integer null:false default 3), `db/migrate/*_add_games_to_results.rb` (`results.games_won/games_lost/games_drawn` integer null:false default 0)
- Modify: `app/models/event.rb` (constants, `FORMATS = %w[multiplayer one_v_one]`, `MATCH_GAMES = [1, 3]`, validations, `one_v_one?`, `multiplayer?`, `format_locked_after_start` (invalid to change `format` once `rounds.exists?`), points defaults by format via `after_initialize` for new records: 1v1 → 3/1/0/3), `app/models/result.rb` (`games` reader → `[games_won, games_lost, games_drawn]`, `game_points` → `3*won + 1*drawn`), `app/models/tournament.rb` (defaults)
- Test: `test/models/event_format_test.rb`

**Interfaces:**
- Produces: `Event#one_v_one?`, `Event#multiplayer?`, `Event#match_games`, `Result#games`, `Result#game_points`.

- [ ] **Step 1: Failing tests** `event_format_test.rb`: default format is `multiplayer` with 7/1/0/7; `Tournament.new(format: "one_v_one")` defaults to 3/1/0/3; `format: "duel"` invalid; `match_games: 2` invalid; changing `format` after a round exists is invalid with error key `:locked`; `Result#game_points` for 2/1/0 → 6, 1/1/1 → 4.
- [ ] **Step 2: Run** → fail. **Step 3: Implement** migrations + model code. **Step 4: Run** `bin/rails test test/models` → PASS. `bin/rails db:migrate` and `db/schema.rb` committed.
- [ ] **Step 5: Commit** `feat: event format and game-score columns`.

### Task 2: MTR tiebreakers for 1v1

**Files:**
- Modify: `app/models/event_participant.rb` (`match_win_rate`, `game_win_rate`, `opponents_match_win_rate`, `opponents_game_win_rate`, `rank_score` branch on `event.one_v_one?`, `standing_columns` per format, `games_played`/`game_points` from current swiss results), `Standings` class if it needs game sums
- Test: `test/models/one_v_one_tiebreakers_test.rb`

**Interfaces:**
- Produces: `EventParticipant#match_win_rate` (Float, floor 0.33), `#game_win_rate` (Float, floor 0.33), `#opponents_match_win_rate`, `#opponents_game_win_rate` (Float; 0.33 when no opponents; byes excluded), `#standing_columns` → `{ points:, omw:, gw:, ogw: }` for 1v1.
- `rank_score` (1v1) = `advancements*10**21 + match_points*10**17 + (omw*10_000).round*10**12 + (gw*10_000).round*10**8 + (ogw*10_000).round*10**4 + tiebreak_salt`.

- [ ] **Step 1: Failing tests** with a 1v1 `TournamentBuilder` helper (add `format:` and a `play_1v1_round!(t, scores: { pod_number => [games_a, games_b] })` to `test/support/tournament_builder.rb`): the MTR Appendix C examples (5-2-1 over 8 rounds → 0.667; 1-3-0 → 0.33 floor; a bye counts 2-0 in the player's own rates but is excluded from OMW); OMW averages opponents' floored rates; ordering by points then OMW then GW then OGW; multiplayer `rank_score` unchanged (existing `tiebreakers_test.rb` stays green).
- [ ] **Step 2–4:** run red, implement, run `bin/rails test test/models` green, rubocop clean.
- [ ] **Step 5: Commit** `feat: MTR tiebreakers for 1v1 events`.

### Task 3: Structure, top cut sizes and bracket names for 1v1

**Files:**
- Modify: `app/services/tournaments/structure.rb` (`suggested(players, format: "multiplayer")`; 1v1 table from the spec §5), `app/services/tournaments/top_cut.rb` (1v1 sizes `[2, 4, 8, 16, 32]`, `rounds_for(size, format:)`, `sizes_for(format)`, `valid_for?(size, format:)`), `app/models/tournament.rb` (`top_cut_size` validation by format; `suggested_structure` passes format; `single_elimination_round_name` for 1v1: Finals / Semifinals / Quarterfinals / Round of 16 / Round of 32; `number_of_single_elimination_rounds` for 1v1 = log2(size); allow `swiss_rounds_count == 0` for 1v1 and the transition `registration_closed → single_elimination` only then), `app/helpers/tournaments_helper.rb` (`top_cut_options` per format, `structure_suggestion` per format)
- Test: `test/services/tournaments/structure_test.rb`, `top_cut_test.rb`, `test/models/tournament_test.rb` (extend)

**Interfaces:**
- Produces: `Tournaments::Structure.suggested(n, format:)`, `Tournaments::TopCut.sizes_for(format)`, `.rounds_for(size, format:)`.

- [ ] Tests for the Appendix E table rows (4 → [0, 4]; 8 → [0, 8]; 9 → [5, 4]; 17 → [5, 8]; 33 → [6, 8]; 65 → [7, 8]; 129 → [8, 8]; 227 → [9, 8]; 410 → [10, 8]); multiplayer rows unchanged; `top_cut_size: 10` invalid for 1v1, `8` valid; a 1v1 with `swiss_rounds_count: 0` moves `registration_closed → single_elimination` and a multiplayer one still cannot.
- [ ] Implement, green, rubocop. Commit `feat: 1v1 structure suggestions and cut sizes`.

### Task 4: 1v1 Swiss pairer, byes and bracket

**Files:**
- Create: `app/services/tournaments/one_v_one_pairer.rb`
- Modify: `app/jobs/tournaments/create_pods_job.rb` (dispatch: `return Tournaments::OneVOnePairer.call(round) if round.event.one_v_one?` before the multiplayer path), `app/jobs/tournaments/create_single_elimination_pods_job.rb` (1v1 branch: first cut round pairs top N by `rank_score` as 1vN, 2vN-1 …; later rounds pair winners of pods `i` and `k+1-i` of the previous round; losers get `Eliminated`, no byes), `app/models/pod.rb` (`sit_participants!` 1v1: two seatings, seeded coin flip, `assigned_by: "random"` — add to the Seating `assigned_by` inclusion list), `app/models/seating.rb`
- Test: `test/services/tournaments/one_v_one_pairer_test.rb`, `test/jobs/tournaments/create_single_elimination_pods_job_test.rb` (extend)

**Interfaces:**
- Produces: `Tournaments::OneVOnePairer.call(round)` → builds `round.pods` (size 2) with seatings and, for an odd field, one `Advance` result (games 2/0/0) for the bye player; idempotent per round (raises if pods exist).

- [ ] **Tests:** 16 players, 5 rounds with seeded random results → zero rematches; 15 players → exactly one bye per round, to the lowest-ranked player without a prior bye, never the same player twice; pair-down: a group of 3 at 6 points sends its lowest member to the 3-point group; last round pairs top-down (rank 1 vs rank 2 when both lead); deterministic for the same seed; `pods.size == 2` and two seatings each with `assigned_by == "random"`. Bracket: Top 8 with ranks 1..8 → pods (1,8),(2,7),(3,6),(4,5) in that order; with upsets (8 beats 1, 5 beats 4) the next round pairs 8 vs 5 and 2/7-winner vs 3/6-winner.
- [ ] Implement (use `Tournaments::RematchRepair` for repairs with the same escalating gap as `CreatePodsJob`), green, rubocop. Commit `feat: 1v1 Swiss pairings, byes and bracket`.

### Task 5: Game scores in results (service, organizer card, player report)

**Files:**
- Modify: `app/services/results/apply.rb` (`games:` keyword `{ winner: [w, l, d] }` or for Draw `{ games: [w, l, d] }`; validates against `event.match_games`: bo3 allows 2-0, 2-1, draw 1-1 / 0-0 (+ drawn games), bo1 allows 1-0 and draw 0-0-1; writes the three columns on both results; multiplayer callers unchanged), `app/services/results/report.rb` (pending JSON `games`), `app/services/results/confirm.rb` (passes games through), `app/controllers/organizer/results_controller.rb` (+ `games` params), `app/controllers/play/reports_controller.rb`, `app/views/organizer/pods/_pod.html.erb` + `_state.html.erb` (1v1 branch: after tapping a row, score buttons "2-0" / "2-1" (bo3) or "1-0" (bo1); Draw opens "1-1" / "0-0"), `app/javascript/controllers/pod_result_controller.js` (score selection → hidden field), `app/views/play/reports/new.html.erb` (1v1: winner + score), locales en/pt (`rounds.score_2_0` …)
- Test: `test/services/results/apply_test.rb` (extend), `test/controllers/organizer/pod_card_test.rb`, `test/controllers/play/reports_test.rb`, `test/system/organizer_round_flow_test.rb` (one 1v1 case: tap row → 2-1 → card completed with "2-1")

- [ ] Tests first (incl. the impossible-score refusals), implement, green, rubocop. Commit `feat: 1v1 game scores in results and result entry`.

### Task 6: Format-aware views, form and feeds

**Files:**
- Modify: `app/views/organizer/tournaments/_form.html.erb` (format select on new, disabled on edit; `match_games` select shown for 1v1 via Stimulus `format-fields`; points defaults switch 7/1/0/7 ↔ 3/1/0/3 client-side when untouched), `app/controllers/organizer/tournaments_controller.rb` (permit `format`, `match_games`), `app/views/play/pairings/_table.html.erb`, `app/views/play/tables/_table.html.erb`, `app/views/organizer/rounds/_seats.html.erb` (print/slips), `app/views/organizer/pods/_state.html.erb` (no seat squares for 1v1, show "2-1"), `app/views/event_participants/index.html.erb` + `_event_participant.html.erb`, `app/views/organizer/event_participants/*` (columns per format, no seat grid), `app/views/tournaments/_standings_help.html.erb` (per format), `app/views/play/events/show.html.erb` (badge "1v1 · Bo3"), `app/queries/profiles/history.rb` + `app/views/profiles/_event_row.html.erb` (no seats for 1v1), `app/serializers/feeds/{standings,rounds,info}.rb` (1v1: `omw/gw/ogw`, no `seats`; tables `games`; info `format`, `matchGames`), `app/models/event_participant.rb` `seat_counts_for` returns empty for 1v1
- Test: controller tests for each page with a 1v1 fixture tournament (one assertion per page: no `data-seat` squares, score shown, columns), `test/serializers/feeds/*` (1v1 shapes), form test (format locked on edit)

- [ ] Tests, implement, green, rubocop. Commit `feat: format-aware pages, form and feeds`.

### Task 7: Docs, simulation guard and whole-branch verification

**Files:**
- Modify: `CLAUDE.md` (Formats section), `README.md`, `docs/superpowers/notes/2026-11-04-1v1-formats-research.md` (link to spec)
- Run: `bin/rails test`, `bin/rails test:system`, `bin/rails "grindin:simulate[500]"`, `bin/rubocop`

- [ ] Update docs; run everything; commit `docs: event formats`.

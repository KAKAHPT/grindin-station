# M11 Uneven Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a multiplayer tournament choose between pods of 3 and byes for an uneven field, drop pods of 5, and keep the same player from repeating a pod of 3 or a bye while a legal swap exists.

**Architecture:** One new column `events.uneven_field`, locked with the structure. `UnevenPodGenerator` becomes a pure shape table (pod sizes + bye count) for both modes. `CreatePodsJob` hands out byes (Advance results, as 1v1 does) from the bottom of the pairing order by lowest short count before building pods, and runs a new `ShortPodRepair` pass after `RematchRepair`. The simulator gains the repetition measure and the gate.

**Tech Stack:** Rails 8.1, Minitest, existing `Tournaments::*` services, Prosopite (N+1 raises in test).

**Spec:** `docs/superpowers/specs/2026-11-05-m11-uneven-field.md`

## Global Constraints

- `Event::UNEVEN_FIELDS = %w[pods_of_three byes]`; column default `"pods_of_three"`; 1v1 normalised to `"pods_of_three"` by `before_validation` (spec §5).
- Pods of 5 never exist: `Event::LARGER_POD_SIZE` is removed (spec §6); `EventParticipant.empty_seat_counts` keeps `(1..5)`.
- Shape table (spec §3): `r = n % 4`. `pods_of_three`: r=0 all 4s; r=1 → `n = 5`: `[4]` + 1 bye, `n ≥ 9`: 4s + `[3,3,3]`; r=2 → 4s + `[3,3]`; r=3 → 4s + `[3]`. `byes`: r=1 → 4s + 1 bye; r=2 → 4s + 2 byes; r=3 → 4s + `[3]`. Pods of 3 are always the last pods.
- Short count = Swiss rounds of this event in a pod of size 3 **plus** Swiss byes (spec §4).
- Bye = `Advance.create!(round:, event_participant:)` in the `SwissRound`, no pod; worth `event.points_bye` (already how `number_of_byes` scores it).
- `ShortPodRepair` runs after `RematchRepair`, never adds a rematch, uses the same gap ladder as `CreatePodsJob#rematch_gaps` (spec §4.2).
- Existing multiplayer behaviour for fields with `r ∈ {0, 2, 3}` and `n ≥ 6` stays byte-identical in `pods_of_three` mode (existing `CreatePodsJobTest` cases pass unchanged, except any that asserts a pod of 5).
- Layout: M7 pieces only (`.field`, `form-help`, `ctable` rows); `grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0. Copy in en/pt/es; `test/i18n_parity_test.rb` passes. pt copy in pt-PT (tu-form).
- Commit with `git commit -- <paths>`; rubocop clean; Prosopite: no per-participant queries in pairing.

## Review Focus

1. A 5-player field in `pods_of_three` mode must give `[4]` + 1 bye, never `[5]` (Task 2 test).
2. Round 2 of a 13-player event must seat none of round 1's pod-of-3 players in a pod of 3 when points allow (Task 3 test with all draws in round 1).
3. Short-pod swaps must never create a rematch (Task 3 unit test with a crafted rematch).
4. Byes must go to the lowest-ordered player with the lowest short count, and `CreatePodsJob` run twice on the same round must not hand out a second bye (Task 2 test: guard like `OneVOnePairer#already_paired?`).
5. Changing `uneven_field` after the Swiss started must fail with `:locked` and show disabled in the form (Tasks 1 and 5).

---

### Task 1: Column, constant, lock, pod-of-5 removal

**Files:**
- Create: `db/migrate/<ts>_add_uneven_field_to_events.rb`
- Modify: `app/models/event.rb` (constant, validation, predicates, 1v1 normalisation, remove `LARGER_POD_SIZE`), `app/models/tournament.rb:43` (`STRUCTURE_ATTRIBUTES`), `config/locales/{en,pt,es}.yml` (locked error under `activerecord.errors.models.tournament.attributes.uneven_field`, attribute label `uneven_field`), `test/models/tournament_test.rb:441` (drop the `LARGER_POD_SIZE` assertion)
- Test: `test/models/tournament_test.rb`

**Interfaces:**
- Produces: `Event::UNEVEN_FIELDS`, `event.uneven_field` (string), `Event#pods_of_three?` / `Event#byes?`.

- [ ] Step 1: Failing tests: default is `"pods_of_three"`; `"fives"` is invalid; updating `uneven_field` on a tournament in `swiss` state adds `:locked`; a 1v1 tournament saved with `uneven_field: "byes"` reads back `"pods_of_three"`; `Event.const_defined?(:LARGER_POD_SIZE)` is false.
- [ ] Step 2: Run `bin/rails test test/models/tournament_test.rb`; expect failures (unknown attribute).
- [ ] Step 3: Migration `add_column :events, :uneven_field, :string, null: false, default: "pods_of_three"`; `bin/rails db:migrate` (dev + test). Constant, `validates :uneven_field, inclusion: { in: UNEVEN_FIELDS }`, predicates, `before_validation { self.uneven_field = "pods_of_three" if one_v_one? }`, `STRUCTURE_ATTRIBUTES` entry, remove `LARGER_POD_SIZE`. Locale keys: label en "Uneven field", pt "Campo desigual", es "Campo desigual"; locked message copied from `pairing_mode`'s.
- [ ] Step 4: `bin/rails test test/models`; expect PASS.
- [ ] Step 5: Commit `feat(m11): uneven_field column, locked with the structure; pods of 5 removed`.

### Task 2: Shape table and byes in `CreatePodsJob`

**Files:**
- Modify: `app/services/tournaments/uneven_pod_generator.rb`, `app/jobs/tournaments/create_pods_job.rb`, `app/models/event_participant.rb` (short count, batched)
- Test: `test/services/tournaments/uneven_pod_generator_test.rb` (create), `test/jobs/tournaments/create_pods_job_test.rb`

**Interfaces:**
- Produces: `Tournaments::UnevenPodGenerator.shape(count, uneven_field) -> { sizes: Array<Integer>, byes: Integer }` (pure, class method; sizes descending, 3s last). `UnevenPodGenerator.new(round).generate_pods!(count)` builds `@round.pods` for `shape(count, round.event.uneven_field)[:sizes]` and returns the shape.
- Produces: `EventParticipant#short_count -> Integer` = `number_of_byes + small_pod_count`; `EventParticipant#small_pod_count` reads `@standings.small_pod_counts(id)` when loaded through the standings, else `EventParticipant.small_pod_counts_for(event, participant_ids: [id])`. `EventParticipant.small_pod_counts_for(event, participant_ids: nil) -> { id => Integer }` in one query: `Seating.joins(pod: :round).where(rounds: { event_id:, type: "SwissRound" }, pods: { size: 3 }).group(:event_participant_id).count`. `Standings#small_pod_counts(id)` loads the hash lazily on first use (like `movement`).
- Consumes: `PlayerSorter#paired_players` / `#random_players` (ordered field), `Event#points_bye`.

- [ ] Step 1: Failing generator tests, table-driven over `n = 4..20` for both modes against the Global Constraints shape table (assert the full `sizes` array and `byes`), plus `shape(5, "pods_of_three") == { sizes: [4], byes: 1 }` and `shape(5, "byes")` the same.
- [ ] Step 2: Failing job tests: (a) 13 players, `byes` mode: round 1 has pods `[4,4,4]`, one `Advance` in the round for the player last in `PlayerSorter.new(round).paired_players` order (all equal points in round 1 → lowest ordered), that participant's `number_of_byes == 1` and `match_points == points_bye`; (b) 14 players, `byes` mode: `[4,4,4]` + 2 Advances; (c) 5 players, default mode: `[4]` + 1 Advance; (d) 17 players default mode: still `[4,4,3,3,3]` (existing test); (e) running `CreatePodsJob.perform_now(round)` a second time on a round that already has pods or results raises `ArgumentError` (mirror `OneVOnePairer#already_paired?`); (f) round 2 of a 13-player `byes` event where round 1 was all draws: the round-1 bye player is not the round-2 bye (short count rule).
- [ ] Step 3: Run the two files; expect failures.
- [ ] Step 4: Implement. `UnevenPodGenerator.shape` per the table; `generate_pods!(count)` builds the sizes. `CreatePodsJob#perform`: guard already paired → order = `pairing_order` → `shape = generator.generate_pods!(order.size)` → `byes = pick_byes(order, shape[:byes])` (walk `order` from the end, pick the lowest `short_count`, ties to the later position; remove and repeat) → `@players_by_rank = order - byes` → match → `repair_rematches!` → transaction: `Advance.create!` per bye, `sit_participants!`. Short counts come through the standings-loaded participants (no per-player query). Remove the pod-of-5 branch.
- [ ] Step 5: `bin/rails test test/jobs test/services test/models`; expect PASS. Check Prosopite raised nothing.
- [ ] Step 6: Commit `feat(m11): shape table for both modes, byes by lowest short count`.

### Task 3: `ShortPodRepair`

**Files:**
- Create: `app/services/tournaments/short_pod_repair.rb`
- Modify: `app/jobs/tournaments/create_pods_job.rb` (call after `repair_rematches!`)
- Test: `test/services/tournaments/short_pod_repair_test.rb` (create), `test/jobs/tournaments/create_pods_job_test.rb`

**Interfaces:**
- Produces: `Tournaments::ShortPodRepair.new(small:, large:, short_count:, points:, met:, max_point_gap:)`; `small` and `large` are Arrays of candidate Arrays (pods of 3 and pods of 4), mutated in place; `short_count`, `points` are callables `player -> Integer`; `met` is `(a, b) -> Boolean`; `max_point_gap` Integer or `Float::INFINITY`. `#repair! -> Integer` = players left in a small pod with `short_count > 0` after the pass. `MAX_SWAPS_PER_POD = 20` like `RematchRepair`.
- Algorithm (spec §4.2): walk `small` last to first, candidates lowest-ranked first (reverse order inside the pod); for a candidate with `short_count > 0`, look at `large` pods nearest by index to this small pod's position in the combined list, in each at the candidate closest in points, and take the first `other` with `short_count(other) < short_count(player)`, `|points(player) - points(other)| <= max_point_gap`, and `rematches_after <= rematches_before` where rematches are counted with `met` over the two pods involved. Swap, repeat until no improving swap or the swap cap.
- Consumes: `RematchRepair`'s opponent sets are not shared; the job passes `met: ->(a, b) { a.opponent_records.any? { |o| o.id == b.id } }` built from the standings-loaded participants (no query per call: precompute `opponent_ids` as `RematchRepair` does and pass a lambda over that hash).

- [ ] Step 1: Failing unit tests with integer players and hashes: (a) small `[[7,8,9]]`, large `[[1,2,3,4],[5,6,10,11]]`, short counts `{7=>1, 8=>0, 9=>0, 10=>0, ...}`, equal points, no rematches → after `repair!` player 7 is in a large pod and `repair!` returned 0; (b) same but `met.(7, x)` true for every x in both large pods' candidates → no swap, returns 1; (c) gap: points 7 has 3, everyone else 0, `max_point_gap: 0` → no swap; `Float::INFINITY` → swap; (d) two repeating players in one small pod and only one eligible partner → returns 1 and the partner swapped with the lowest-ranked repeating player (last in the pod's order).
- [ ] Step 2: Failing job test: 13 players default mode, round 1 all draws (`winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw }`), round 2: none of round 1's pod-of-3 players sit in a pod of 3 (set intersection empty). Second job test: 16 players in `byes` mode is unaffected (no small pods, no byes, pods `[4,4,4,4]`).
- [ ] Step 3: Run; expect failures.
- [ ] Step 4: Implement the service and `CreatePodsJob#repair_short_pods!`: `rematch_gaps.each { |gap| break if ShortPodRepair.new(small:, large:, ..., max_point_gap: gap).repair!.zero? }` where `small = @round.pods.select { |p| p.size == 3 }.map(&:candidates)` and `large` the rest (the arrays are the pods' own `candidates`, so swaps land in the pods). Skip entirely when `small` is empty.
- [ ] Step 5: `bin/rails test test/jobs test/services`; expect PASS, including every pre-existing rematch test.
- [ ] Step 6: Commit `feat(m11): ShortPodRepair keeps pods of 3 from repeating`.

### Task 4: Simulator measure and gate

**Files:**
- Modify: `app/services/tournaments/seat_simulator.rb`, `lib/tasks/grindin.rake`
- Create: `docs/superpowers/notes/2026-11-05-m11-uneven-field.md`
- Test: `test/services/tournaments/seat_simulator_test.rb`

**Interfaces:**
- Produces: `SeatSimulator.new(..., short_repair: true)` (default true; `false` = baseline); `Report#repeat_small_rate` = share of players who sat in a pod of 3 two or more times. The simulator's `pods` stays a pure 4s-then-3s split (spec §3 `pods_of_three`, n ≥ 6; the simulator never has n = 5), then runs `ShortPodRepair` over the arrays with `points: @points`, `short_count:` from a per-player counter the simulator keeps, `met:` always false (rematch repair is not modelled), gap ladder `[0, DRAW_POINTS, WIN_POINTS, 2*WIN_POINTS, ..., Float::INFINITY]`.

- [ ] Step 1: Failing test: `SeatSimulator.new(players: 13, rounds: 4, rng: Random.new(1)).run.repeat_small_rate` is lower than with `short_repair: false` over 50 seeds (mean), and both are between 0 and 1.
- [ ] Step 2: Implement; rake task prints a third block "== short pods (13 players, 4 rounds)" with the mean `repeat_small_rate` for `short_repair: true/false` over `n` seeds, and fails if the repaired mean exceeds the baseline mean or exceeds the recorded level + 0.02. Run `bin/rails "grindin:simulate[2000]"`, record both means in the note, set the recorded level there and in the task.
- [ ] Step 3: `bin/rails test test/services/tournaments/seat_simulator_test.rb` PASS; `bin/rails "grindin:simulate[500]"` OK for every mode.
- [ ] Step 4: Commit `feat(m11): simulation gate for repeated pods of 3`.

### Task 5: Settings, overview, public line, feed, copy, docs

**Files:**
- Modify: `app/views/organizer/tournaments/_form.html.erb` (select + help after the pairing select, inside the same `format_fields_target: "pairing"` block), `app/controllers/organizer/tournaments_controller.rb` (permit `uneven_field`), `app/views/organizer/tournaments/show.html.erb` (row "Uneven field" under Pairing), `app/helpers/organizer_shell_helper.rb` (`uneven_field_name(event)`, nil for 1v1; `uneven_field_options`), `app/helpers/events_helper.rb:46` (`play_format_line` appends `uneven_field_name`), `app/serializers/feeds/info.rb` (`unevenField`, nil for 1v1), `config/locales/{en,pt,es}.yml`, `CLAUDE.md` (Pairing modes bullet gains the uneven-field line), `docs/superpowers/notes/2026-11-04-backlog-after-m6.md` (M11 entry DONE)
- Test: `test/controllers/organizer/tournaments_controller_test.rb`, `test/serializers/feeds/info_test.rb`, `test/controllers/play/events_controller_test.rb`, `test/i18n_parity_test.rb`

**Copy (en; pt-PT and es equivalents):**
- `organizer.uneven_fields.pods_of_three: "Pods of 3"`, `organizer.uneven_fields.byes: "Byes"`
- `organizer.uneven_help.pods_of_three: "When the field is not a multiple of four, the last tables seat three players."`
- `organizer.uneven_help.byes: "Only pods of four; one or two players left over get a bye worth the bye points (three left over still play a pod of three)."`
- `organizer.overview.uneven_field: "Uneven field"`
- `organizer.points_bye_help: "Used for 1v1 byes and when the uneven field is set to byes."` shown as `form-help` under the points grid.
- pt: "Pods de 3", "Byes", "Quando o campo não é múltiplo de quatro, as últimas mesas têm três jogadores.", "Só pods de quatro; quem sobra (um ou dois) recebe um bye com os pontos de bye (três a sobrar jogam um pod de 3).", "Campo desigual", "Usado nos byes de 1v1 e quando o campo desigual está em byes."

- [ ] Step 1: Failing tests: PATCH settings with `uneven_field: "byes"` on a draft tournament persists it; the same on a `swiss` tournament is rejected with the locked error; the settings page shows the select with both options and disabled when locked; a 1v1 tournament's settings page has no `uneven_field` select; feed `unevenField` is `"byes"` for a byes event and nil for 1v1; public event page About line contains "Byes" for a byes event.
- [ ] Step 2: Run; expect failures.
- [ ] Step 3: Implement views, helper, controller permit, serializer, locales, CLAUDE.md and backlog lines.
- [ ] Step 4: `bin/rails test`; `bin/rails test:system`; `bundle exec rubocop`; `grep -rnE "purple|orange-700|dark:|gray-" app/views` → 0.
- [ ] Step 5: Commit `feat(m11): uneven field setting on settings, overview, public line and feed`.

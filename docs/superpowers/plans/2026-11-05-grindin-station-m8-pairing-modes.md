# M8 Pairing Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a multiplayer tournament choose Swiss pods, Power pods or Random pods, with fair seats and rematch repair in every mode.

**Architecture:** One new column `events.pairing_mode`, locked with the structure. `CreatePodsJob` picks the player order and the matcher by mode; everything after the matcher (rematch repair, fair seats) is untouched. The simulator and the simulation gate get a `mode:`.

**Tech Stack:** Rails 8.1, Minitest, existing `Tournaments::*` services.

**Spec:** `docs/superpowers/specs/2026-11-05-m8-pairing-modes.md`

## Global Constraints

- Keep the M7 design on every page touched: existing `card`, `card-title`, `.field`, `button_classes`, chips; no new CSS classes beyond what the Settings select needs (reuse `.field`).
- `grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0.
- Copy in en/pt/es; `test/i18n_parity_test.rb` must pass.
- Multiplayer behaviour in `swiss` mode must be byte-identical to today (existing `CreatePodsJobTest` cases pass unchanged).
- Commit with `git commit -- <paths>` (never sweep other changes); rubocop clean.

## Review Focus

1. A `random` event with the same seed must build the same pods twice (Task 2 test).
2. A `power` event's round 2 must not spread (Task 2 test).
3. Changing the mode after the swiss started must fail with `:locked` in the model and show the field disabled in the form (Tasks 1 and 4 tests).
4. 1v1 events must ignore the column entirely (Task 1 test: `OneVOnePairer` output unchanged with `pairing_mode: "random"`).
5. The simulation gate must still fail when fairness regresses in any mode (Task 3: gate evaluated per mode).

---

### Task 1: Column, constant, lock

**Files:**
- Create: `db/migrate/<ts>_add_pairing_mode_to_events.rb`
- Modify: `app/models/event.rb` (constant + inclusion validation), `app/models/tournament.rb:43` (`STRUCTURE_ATTRIBUTES`), `config/locales/{en,pt,es}.yml` (locked error message for `pairing_mode`, attribute label)
- Test: `test/models/tournament_test.rb` (or the existing event model test file)

**Interfaces:**
- Produces: `Event::PAIRING_MODES = %w[swiss random power]`, `event.pairing_mode` (string), `Event#swiss_pairing?/power_pairing?/random_pairing?` predicates.

- [ ] Step 1: Write failing tests: default is `"swiss"`; `"bubble"` is invalid; updating `pairing_mode` on a tournament in `swiss` state adds `:locked`; a 1v1 tournament with `pairing_mode: "random"` still pairs via `OneVOnePairer` (use `TournamentBuilder.build(format: "one_v_one", players: 8)` and assert pods have size 2).
- [ ] Step 2: Run them, expect failures (unknown attribute).
- [ ] Step 3: Migration `add_column :events, :pairing_mode, :string, null: false, default: "swiss"`; run `bin/rails db:migrate` (dev + test). Add the constant, `validates :pairing_mode, inclusion: { in: PAIRING_MODES }`, predicates, and the `STRUCTURE_ATTRIBUTES` entry. Add the `locked` message under `activerecord.errors.models.tournament.attributes.pairing_mode` and the attribute label `pairing_mode: "Pairing"` in the three locale files.
- [ ] Step 4: Run the tests and `bin/rails test test/models`; expect PASS.
- [ ] Step 5: Commit `feat(m8): pairing_mode column, locked with the structure`.

### Task 2: Mode-aware pairing

**Files:**
- Modify: `app/models/tournament.rb:136-141` (`swiss_round_strategy`), `app/services/tournaments/player_sorter.rb` (add `random_players(rng)`), `app/jobs/tournaments/create_pods_job.rb` (order + gaps by mode)
- Test: `test/jobs/tournaments/create_pods_job_test.rb`, `test/services/tournaments/player_sorter_test.rb`

**Interfaces:**
- Consumes: Task 1 predicates.
- Produces: `PlayerSorter#random_players(rng)` → the round's participants shuffled with `rng` then `self.class.deal(field, seat_counts)` as one group; `CreatePodsJob#rematch_gaps` returns `[Float::INFINITY]` for random; `Tournament#swiss_round_strategy` returns `:standard` for power/random.

- [ ] Step 1: Write failing tests per spec §5 (power no spread; random ignores points; random deterministic per seed; random 0 rematches after 16 draws × 3 rounds; `assigned_by: "fair"` in every mode). Reuse helpers in the existing job test.
- [ ] Step 2: Run, expect failures.
- [ ] Step 3: Implement. RNG: `Random.new(Digest::SHA256.hexdigest("#{event.seed}:#{round.number}:pairing")[0, 8].hex)`; `event.seed` is set by `snapshot_structure` when the state turns to swiss, fall back to `0` when nil.
- [ ] Step 4: Run `bin/rails test test/jobs test/services`; expect PASS, including the unchanged swiss cases.
- [ ] Step 5: Commit `feat(m8): power and random pairing in CreatePodsJob`.

### Task 3: Simulator and gate per mode

**Files:**
- Modify: `app/services/tournaments/seat_simulator.rb` (`mode:` kwarg), `lib/tasks/grindin.rake` (loop modes, gate per mode), `.github/workflows/ci.yml` only if the invocation must change (it should not)
- Create: `docs/superpowers/notes/2026-11-05-m8-pairing-modes.md` (measured values per mode, SIM_SEED=42, n=2000)
- Test: `test/services/tournaments/seat_simulator_test.rb`

- [ ] Step 1: Failing test: `SeatSimulator.new(players: 16, rounds: 5, rng: Random.new(1), seating: :fair, mode: :random).run` returns a report; `mode: :bubble` raises `ArgumentError`.
- [ ] Step 2: Implement `mode:` (default `:swiss`); `:random` → `@players.shuffle(random: @rng)` then `PlayerSorter.deal(all, @seat_counts)` as one group; `:power` identical to `:swiss` in the simulator (document why in a comment).
- [ ] Step 3: Rake task: for each mode print the table and evaluate the gate; exit 1 if any fails. Run `bin/rails "grindin:simulate[2000]"` and record the numbers in the note.
- [ ] Step 4: Tests pass; commit `feat(m8): simulation gate per pairing mode`.

### Task 4: Settings, overview, public line, feed, copy

**Files:**
- Modify: `app/views/organizer/tournaments/_form.html.erb` (Structure section), `app/controllers/organizer/tournaments_controller.rb` (permit `pairing_mode`), the organizer Overview partial that lists structure (find it under `app/views/organizer/tournaments/show.html.erb` / `_shell`), `app/views/play/events/show.html.erb` or the `shared/_event_header` `line:` built by `Play::EventsController`, `app/serializers/feeds/info.rb`, `config/locales/{en,pt,es}.yml`
- Test: `test/controllers/organizer/tournaments_controller_test.rb`, `test/serializers/feeds/info_test.rb` (or the existing feed test), `test/i18n_parity_test.rb`

- [ ] Step 1: Failing tests: PATCH with `pairing_mode: "power"` before swiss persists; after swiss returns 422 with the locked message; the organizer show page and the public event page contain "Power pods"; info feed has `pairingMode`.
- [ ] Step 2: Implement with the existing `.field` select markup used by `top_cut_size`; help text as a single `<p class="help">` (whatever class `organizer.points_help` uses) listing the three one-liners; multiplayer-only via the existing format-fields target. Keys: `organizer.pairing_modes.{swiss,power,random}` and `organizer.pairing_help.{swiss,power,random}`, `feeds` untouched except the key.
- [ ] Step 3: `bin/rails test` green, `bin/rubocop` clean, parity test green.
- [ ] Step 4: Commit `feat(m8): pairing mode in settings, overview, public page and info feed`.

### Task 5: Docs and whole-branch verification

**Files:**
- Modify: `CLAUDE.md` (Key Business Logic: pairing modes; Routes untouched), `docs/superpowers/notes/2026-11-04-backlog-after-m6.md` (mark M8 done)

- [ ] Step 1: Update docs.
- [ ] Step 2: `bin/rails test && bin/rails test:system && bin/rubocop && bin/brakeman -q && bin/rails "grindin:simulate[500]"` all green.
- [ ] Step 3: Commit `docs(m8): pairing modes`.

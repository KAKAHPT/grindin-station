# M15 Game Formats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1v1 tournaments carry a Magic game format; every place that filters or rates by format uses the play pool (`multiplayer` or the 1v1 game format), and Elo is computed per pool.

**Architecture:** `events.game_format` + `Event#play`; `Event.with_play` scope; `ranking_contributions.format` stores the play; `elo_ratings.play` joins the unique key; `Rankings::Rebuild` replays Elo per (season, play); the `play` filter on `/rankings`, `/events` and `/admin/events` lists `Event::PLAYS`; the Leaderboard defaults to `multiplayer`.

**Tech Stack:** Rails 8.1, Hotwire, Minitest, Prosopite.

**Spec:** `docs/superpowers/specs/2026-11-05-m15-game-formats.md`

## Global Constraints

- `Event::GAME_FORMATS = %w[commander standard pioneer modern legacy vintage pauper other]`; column default `"commander"`; multiplayer forced to `commander` by `before_validation`; 1v1 must be one of the others (validation); migration backfills 1v1 rows to `other`.
- `Event#play` = `one_v_one? ? game_format : "multiplayer"`; `Event::PLAYS = ["multiplayer"] + (GAME_FORMATS - ["commander"])`; labels `play.formats.<play>` (en: "cEDH · pods of four", "Standard", "Pioneer", "Modern", "Legacy", "Vintage", "Pauper", "Other 1v1"; pt/es translated, pods line as today's `play.header.multiplayer`).
- `game_format` is in `Tournament::STRUCTURE_ATTRIBUTES` (locked after the Swiss starts) and permitted in the organizer tournaments controller; leagues are multiplayer only (no field).
- `event_format_label(event)` → multiplayer: unchanged; 1v1: "Legacy · Bo3" (`play.events.format_badge` becomes "%{format} · Bo%{games}").
- `ranking_contributions.format` = `event.play`; `elo_ratings.play` string not null, unique `[player_id, season, play]` (nulls_not_distinct); the old two-column index is dropped.
- Leaderboard: `play` defaults to `multiplayer`, no "All formats" option on that tab; Points and Teams keep "All formats" default.
- Copy en/pt-PT/es with parity; colour grep 0; rubocop; Prosopite; only task files committed (`git commit -- <paths>`); one implementer at a time.

## Review Focus

1. A multiplayer event posted with `game_format: "legacy"` must end up `commander` (Task 1 test).
2. `/rankings?tab=elo` without `play` must show the multiplayer pool, with the chip (Task 2 test).
3. A player with a Legacy and a pod event must have two rating rows per season and the all-time pair (Task 2 test).
4. `/events?play=legacy` must not list Modern or pod events (Task 2 test).
5. The migration must not raise on a database with existing 1v1 events and old `elo_ratings` rows (Task 2: migration test or a runner check in dev).

---

### Task 1: Column, model, settings, labels, feed

**Files:**
- Create: `db/migrate/<ts>_add_game_format_to_events.rb` (add column with default, then `UPDATE events SET game_format = 'other' WHERE format = 'one_v_one'`)
- Modify: `app/models/event.rb` (constants, validation, normalisation, `#play`, `scope :with_play`), `app/models/tournament.rb` (`STRUCTURE_ATTRIBUTES`), `app/controllers/organizer/tournaments_controller.rb` (permit), `app/views/organizer/tournaments/_form.html.erb` (select in the 1v1 block next to Best of, `disabled: locked`), `app/helpers/events_helper.rb` (`event_format_label`, `play_label(play)`), `app/serializers/feeds/info.rb` (`gameFormat`), `app/views/organizer/tournaments/show.html.erb` (Overview row "Game format" for 1v1), `config/locales/{en,pt,es}.yml`, `db/seeds.rb` (1v1 demo events get a format if any)
- Test: `test/models/event_format_test.rb` (exists), `test/controllers/organizer/tournaments_controller_test.rb`, `test/controllers/play/events_controller_test.rb`, `test/serializers/feeds/info_test.rb`, `test/helpers/*` as appropriate

- [ ] Step 1: Failing tests: validation (1v1 needs a non-commander format; multiplayer forced to commander; "chess" invalid); `play` values; `with_play("legacy")` and `with_play("multiplayer")`; Settings shows the select only for 1v1 and saves it; locked after Swiss; About line "Legacy · Bo3"; ticket line on /events; feed `gameFormat`; Overview row.
- [ ] Step 2: Run; expect failures. Step 3: implement; migrate dev + test. Step 4: tests + rubocop + parity + colour grep.
- [ ] Step 5: Commit `feat(m15): game format for 1v1 tournaments`.

### Task 2: Play pools in rankings, Elo and filters; docs

**Files:**
- Create: `db/migrate/<ts>_add_play_to_elo_ratings.rb` (add `play` string default `"multiplayer"` not null, drop the old unique index, add unique `[player_id, season, play]` nulls_not_distinct; `DELETE FROM elo_ratings` so the next rebuild fills it)
- Modify: `app/models/elo_rating.rb`, `app/services/rankings/contributions.rb` (`format: event.play`), `app/services/rankings/rebuild.rb` (Elo per (season, play) and (nil, play)), `app/queries/rankings/board.rb` (play filter over `Event::PLAYS`; Elo rows from the pool; Leaderboard default `multiplayer`), `app/helpers/rankings_helper.rb` (options/labels/chips; no "All formats" on the Leaderboard), `app/views/rankings/_how_elo.html.erb` (+ pt/es copy: per-format ratings), `app/controllers/concerns/event_tickets.rb` + `app/helpers/event_filters_helper.rb` (play options = `Event::PLAYS`, filter via `with_play`), `app/controllers/admin/events_controller.rb` + view (format filter → play), `app/queries/admin/invitational.rb` if it filters by format, `CLAUDE.md`, `docs/superpowers/notes/2026-11-04-backlog-after-m6.md` (M15 DONE), `test/support/rankings_fixture.rb`
- Test: `test/services/rankings/{contributions,rebuild}_test.rb`, `test/queries/rankings/board_test.rb`, `test/controllers/rankings_controller_test.rb`, `test/controllers/events_controller_test.rb`, `test/controllers/admin/events_controller_test.rb`, `test/system/rankings_test.rb` (adjust)

- [ ] Step 1: Failing tests per spec acceptance 2–6 (two pools per player; Leaderboard default and chip; `/events?play=legacy`; admin filter; contributions store the play).
- [ ] Step 2: Run; expect failures. Step 3: implement; migrate dev + test; `bin/rails rankings:rebuild` in dev. Step 4: `bin/rails test`, `bin/rails test:system`, rubocop, parity, colour grep, `bin/brakeman --no-pager`.
- [ ] Step 5: Commit `feat(m15): play pools — rankings filters and Elo per game format`.

# M10 Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give organizers the files they need to report an event on Wizards EventLink, Melee and TopDeck, plus a printable results sheet and standings/rounds CSVs.

**Architecture:** Five CSV POROs in `app/services/exports/`, one `Organizer::ExportsController` with one action per file plus the sheet, a Wizards e-mail on `players`, an Export card on the Overview tab. Every download is audited.

**Tech Stack:** Rails 8.1, Ruby `csv`, existing `print` layout, Minitest.

**Spec:** `docs/superpowers/specs/2026-11-05-m10-export.md`

## Global Constraints

- M7 design only (`card`, `card-title`, `ctable`, `button_classes`, `.field`); `grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0.
- `wizards_email` never rendered on a public page.
- CSVs: UTF-8 BOM, CRLF, attachment filename `<slug>-<kind>.csv`.
- Copy in en/pt/es; parity test passes.
- Commit with `git commit -- <paths>`; rubocop, brakeman clean.

## Review Focus

1. A player with no account e-mail and no Wizards e-mail must appear by name in `players.csv`, never as an empty line (Task 2 test).
2. A judge must not be able to download exports (Task 3 test: 302 to organizer root with the not-allowed flash).
3. A 1v1 event's `standings.csv` must carry omw/gw/ogw, a multiplayer one winRate/opponentWinRate (Task 2 tests).
4. `pairings.csv` with no published round must respond 404, not crash (Task 3 test).
5. The sheet must list only closed rounds for an ongoing event (Task 3 test with one closed and one open round).

---

### Task 1: Wizards e-mail on players

**Files:**
- Create: `db/migrate/<ts>_add_wizards_email_to_players.rb`
- Modify: `app/models/player.rb` (`reporting_email`, format validation `allow_blank`), `app/controllers/accounts_controller.rb` (permit `player_attributes: [:wizards_email]` or a dedicated param), `app/views/accounts/show.html.erb` (`.field` after e-mail), `app/services/accounts/anonymize.rb` (clear it), `app/helpers/roster_helper.rb` or the roster desk row (show reporting e-mail to staff where the account e-mail is shown today, if it is), `config/locales/{en,pt,es}.yml`
- Test: `test/models/player_test.rb`, `test/controllers/accounts_controller_test.rb`, `test/services/accounts/anonymize_test.rb`, `test/controllers/profiles_controller_test.rb` (not rendered)

- [ ] Step 1: Failing tests; Step 2: implement; Step 3: green; commit `feat(m10): Wizards account e-mail on players`.

### Task 2: CSV exports

**Files:**
- Create: `app/services/exports/csv_file.rb` (shared: BOM + CRLF `generate(headers, rows)`), `app/services/exports/players.rb`, `melee.rb`, `standings.rb`, `rounds.rb`, `pairings.rb`
- Test: `test/services/exports/*_test.rb`

**Interfaces:**
- Produces: `Exports::Players.call(event)`, `Exports::Melee.call(event)`, `Exports::Standings.call(event)`, `Exports::Rounds.call(event)`, `Exports::Pairings.call(event, round:)` → String. Standings order via `Feeds::Standings.ranked(event)`; results via `Result.current`.

- [ ] Step 1: Failing tests per spec §5 (multiplayer after two `TournamentBuilder.play_round!`, one 1v1 with `play_1v1_round!`).
- [ ] Step 2: Implement; Step 3: green; commit `feat(m10): CSV exports (players, melee, standings, rounds, pairings)`.

### Task 3: Controller, routes, sheet, Overview card, audit, copy

**Files:**
- Create: `app/controllers/organizer/exports_controller.rb` (`allow_roles :organizer, :scorekeeper`; actions `players`, `melee`, `standings`, `rounds`, `pairings`, `sheet`), `app/views/organizer/exports/sheet.html.erb` (`print` layout), `app/views/organizer/tournaments/_export_card.html.erb`
- Modify: `config/routes.rb` (`scope :export` under tournaments and leagues: `get "export/players" => "exports#players"` …), `app/views/organizer/tournaments/show.html.erb` (render the card on Overview), leagues show if it has an Overview, `config/locales/{en,pt,es}.yml`
- Test: `test/controllers/organizer/exports_controller_test.rb`, `test/views/organizer/overview_export_card_test.rb` (or inside the tournaments controller test)

- [ ] Step 1: Failing tests (roles, headers, audit row, 404 pairings without a published round, sheet lists closed rounds only, card rows).
- [ ] Step 2: Implement; `Audit.record("data_exported", event:, kind:)` — add `data_exported` to `AuditEvent::ACTIONS`.
- [ ] Step 3: green, rubocop, parity; commit `feat(m10): export downloads, results sheet and Overview card`.

### Task 4: Docs and whole-branch verification

- [ ] `CLAUDE.md` (Routes: export paths; players.wizards_email), backlog M10 done; `bin/rails test && bin/rails test:system && bin/rubocop && bin/brakeman -q` green; commit `docs(m10): export`.

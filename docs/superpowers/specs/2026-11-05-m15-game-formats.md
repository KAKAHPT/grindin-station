# M15 — Game formats for 1v1 (Legacy, Modern, Pauper, Standard…)

**Date:** 2026-11-05. **Status:** approved by the organiser ("tem que ser"). **Scope:** 1v1 tournaments get a Magic game format; rankings, Elo, filters, tickets and the About card stop mixing 1v1 formats.

## 1. Problem

Every 1v1 event is a single bucket ("1v1 · Bo3"). The rankings, the Elo leaderboard and the event filters would mix Legacy, Modern and Pauper results. Multiplayer stays one pool (cEDH pods).

## 2. Decisions

| # | Decision |
|---|----------|
| D1 | `events.game_format` string, not null, default `"commander"`. `Event::GAME_FORMATS = %w[commander standard pioneer modern legacy vintage pauper other]`. Multiplayer events are always `commander` (normalised in `before_validation`, like `pairing_mode`); 1v1 events pick one of the others (`commander` is not offered for 1v1; existing 1v1 rows are backfilled to `other`). Validated by inclusion. |
| D2 | **Play pool** = the value used everywhere a format is filtered or rated: `Event#play` → `"multiplayer"` for multiplayer, else the `game_format` (`legacy`, `modern`, …). `Event::PLAYS = ["multiplayer"] + (GAME_FORMATS - ["commander"])`. Labels: `play.formats.multiplayer` "cEDH · pods of four", `legacy` "Legacy", `modern` "Modern", `pauper` "Pauper", `standard` "Standard", `pioneer` "Pioneer", `vintage` "Vintage", `other` "Other 1v1". |
| D3 | Settings: a "Game format" select in the 1v1 part of the Structure block (next to Best of), shown only for 1v1 (the `format_fields` controller already toggles 1v1 fields), locked with the structure after the Swiss starts. Create form too. |
| D4 | Labels everywhere a 1v1 event is described: `event_format_label` → "Legacy · Bo3" (format name, then best-of); tickets' format line, About card, organizer header, feeds `format` key stays (`one_v_one`) and a new `gameFormat` key carries the game format. |
| D5 | `ranking_contributions.format` now stores the **play** (`multiplayer`, `legacy`, …) instead of `multiplayer`/`one_v_one`; the `play` URL filter on `/rankings` and `/events` lists every `Event::PLAYS` value with its label ("All formats" + the eight). `/events` filters by `Event#play` (a scope `Event.with_play(value)`: `format = multiplayer` or `game_format = value`). Admin events filter the same. |
| D6 | **Elo per play pool.** `elo_ratings` gains `play` string not null (part of the unique index with `player_id` and `season`). `Rankings::Rebuild` runs one Elo replay per (season, play) and per (all time, play); the Leaderboard tab requires a play pool: the `play` filter defaults to `multiplayer` on that tab (chip shown, ✕ goes back to multiplayer, no "All formats" option on the Leaderboard), and lists the players rated in that pool. Points and Teams keep "All formats" as the default. The strip's "players" counts the listed rows. |
| D7 | Copy en/pt-PT/es; the Leaderboard dialog's house rules say ratings are per format. |
| D8 | Seeds and dev demo data: 1v1 demo events, if any, get a game format. |

## 3. Acceptance

1. A 1v1 tournament saved without a game format is invalid; a multiplayer one is forced to `commander`; `/t/:slug` About shows "Legacy · Bo3"; the ticket line too.
2. `/events?play=legacy` lists only Legacy events; `play=multiplayer` only pods; the select offers the eight options.
3. After a rebuild, `ranking_contributions.format` holds the play; `/rankings?play=modern` lists only Modern contributions.
4. `elo_ratings` has one row per (player, season, play); the Leaderboard defaults to `multiplayer`, `?tab=elo&play=legacy` shows the Legacy ratings, and a player rated in both pools has two independent ratings (unit test on `Rebuild` with one Legacy and one pod event).
5. The feeds info carries `gameFormat`; the admin events filter offers the plays.
6. Migration backfills existing 1v1 events to `other` and multiplayer to `commander`; `elo_ratings` are wiped and rebuilt (the job runs after migrate via `rankings:rebuild`, noted in the PR).

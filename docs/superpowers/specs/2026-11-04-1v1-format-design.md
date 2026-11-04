# Event formats: multiplayer pods and 1v1 — design (2026-11-04)

Owner's ask: "quando vais organizar um evento, escolhes o formato" so stores that play 1v1 formats
(Standard, Modern, Pioneer, Limited, other TCGs) can use Grindin Station. Multiplayer stays exactly as it is.
Research with sources: `docs/superpowers/notes/2026-11-04-1v1-formats-research.md`.

## 1. Scope

- A **format** per event, chosen at creation and frozen afterwards: `multiplayer` (default; pods of 3–5, seat
  fairness, cEDH tiebreakers; nothing changes) or `one_v_one` (tables of two).
- 1v1 v1 covers: Swiss pairings by match points with pair-down, no rematches and byes; best-of-three matches
  with game scores (and best-of-one); MTR tiebreakers; single-elimination top cut with the MTR bracket;
  recommended rounds/cut from MTR Appendix E; organizer and player result entry with game scores; standings,
  pairings, print, feeds and profile history aware of the format.
- Out of scope for v1: two-game matches, team formats, Limited draft playoffs, per-game tiebreaker variants
  (FaB, Pokémon OOMW%), seeding round 1 by rating. Leagues are multiplayer only.

## 2. Data

- `events.format` string, not null, default `"multiplayer"`, values `multiplayer | one_v_one`. Locked once the
  event has rounds (validation `format_locked_after_start`, like the structure lock).
- `events.match_games` integer, default 3, allowed `1 | 3` (best-of-N); only meaningful for `one_v_one`.
- Points defaults by format at creation: multiplayer 7/1/0/7 (today); 1v1 **3/1/0/3** (MTR). Still editable
  until the swiss starts, as today.
- `results.games_won`, `results.games_lost`, `results.games_drawn` integer, default 0. Filled for 1v1 results
  only (a Win 2-1 → winner 2/1/0, loser 1/2/0; a drawn match 1-1-1 → both 1/1/1; a bye → 2/0/0). Multiplayer
  rows stay 0 and are ignored.
- `pods.size` becomes 2 for 1v1 pods. No other schema change.

## 3. Pairing (1v1)

`Tournaments::OneVOnePairer.call(round)` replaces `UnevenPodGenerator` + `PlayerSorter` + strategies when
`event.one_v_one?` (dispatch in `CreatePodsJob`):

1. Players = active participants (not dropped, not waitlisted). If odd, the **bye** goes to the lowest-ranked
   player (by `rank_score`) who has not had a bye; recorded as an `Advance` result with no seating, 2-0 games
   (today's Swiss-bye representation).
2. Round 1: shuffle with the event seed, pair 1-2, 3-4, … Later rounds: sort by `rank_score` desc, walk the
   list top-down grouping by `match_points`; inside a group pair in a seeded random order; an odd group
   sends its last player down to the next group (pair-down); the last round pairs each group **top-down**
   (highest vs next) instead of random, EventLink's "power pairing".
3. Rematch repair: reuse `Tournaments::RematchRepair` (size-agnostic) with the same escalating point gap as
   today.
4. Seats: order 1/2 is a seeded coin flip, `assigned_by: "random"`; no fairness, no seat counts.
5. Pods are `Pod` rows with `size: 2`; everything downstream (results, broadcasts, judge calls) works unchanged.

## 4. Scoring and standings (1v1)

- Match points use the event's points (3/1/0, bye 3). `EventParticipant#rank_score` branches on format:
  `advancements·1e21 + match_points·1e17 + omw4·1e12 + gw4·1e8 + ogw4·1e4 + tiebreak_salt` where `x4` is the
  percentage × 10 000 rounded. Integer arithmetic (no Float).
- `match_win_rate` = match points ÷ (points_win × rounds played), floored at 0.33; `game_win_rate` = game
  points ÷ (3 × games played) with game points 3/1/0, floored at 0.33; `opponents_match_win_rate` and
  `opponents_game_win_rate` = averages over opponents, each opponent floored, **byes excluded**; a player with
  no opponents yet → 0.33.
- `standing_columns` for 1v1: points, omw, gw, ogw, W-L-D (no seats, no beaten/unique). Standings help text per
  format. Win % column stays (games or matches? → matches, the same as today's definition).
- Single-elimination: `Advance`/`Eliminated` as today; the cut bracket (§5) decides positions; `FinishTournamentJob`
  unchanged.

## 5. Structure and top cut (1v1)

- `Tournaments::Structure.suggested(players, format:)`: 1v1 per MTR Appendix E: `<4 → [0, 0]`, `4 → [0, 4]`, `5..8 → [0, 8]`
  (straight single elimination, no Swiss; a short field gets walkovers for the top seeds), `9..16 → [5, 4]`, `17..32 → [5, 8]`, `33..64 → [6, 8]`,
  `65..128 → [7, 8]`, `129..226 → [8, 8]`, `227..409 → [9, 8]`, `410.. → [10, 8]`. Multiplayer unchanged.
- `Tournaments::TopCut` gains 1v1 sizes `2, 4, 8, 16, 32`: rounds = log2(size), one table of 2 per pair, no byes.
  Validation of `top_cut_size` uses the format's sizes.
- Bracket: first cut round pairs by final Swiss rank `1v8, 2v7, 3v6, 4v5` (pods numbered 1..k in that order);
  each next cut round pairs the winners of pods `i` and `k+1-i`. Names: Finals / Semifinals / Quarterfinals /
  Round of 16 / Round of 32.
- A swiss_rounds_count of 0 is allowed for 1v1 (straight single elimination): `registration_closed → single_elimination`
  is a legal transition when `swiss_rounds_count == 0`. In that case the cut may be the next power of two at or
  above the field (5–8 players → Top 8): vacant slots are walkovers for the top seeds (§5 bracket).
- A bo3 match stopped on time at 1-0 is recorded 1-0-1 (the unfinished game is a draw, MTR); 1-0-0 is also accepted.

## 6. Results entry (1v1)

- Organizer pod card (1v1 variant of `_pod`/`_state`): two rows (Player A, Player B). Tap a row → inline
  confirm with score buttons **2-0 · 2-1** (bo3) or **1-0** (bo1); footer **Draw** opens **1-1 · 0-0** (bo3; a
  bo1 draw is 0-0-1). `Results::Apply` accepts `games: { winner: [w, l, d], loser: [...] }` and writes the
  columns; existing callers without `games` keep working (multiplayer).
- Player self-report (`play/reports/new`): the same choices on the phone. Pending result JSON gains `games`.
  Confirm/contest/timeout unchanged.
- Time called in the cut (1v1): MTR is "highest seed advances" by default, same as today's rule.

## 7. Views and feeds

- Format-aware partials: pod card and state, public pairing card, my-table, print pairings and slips (two names,
  "Table N", no seat squares), standings (columns per format), roster (no seat grid), profile history (no seats),
  the event page badge ("1v1 · Bo3").
- Form: `format` select on **new** only (disabled on edit), `match_games` select shown for 1v1, points defaults
  switch with the format (Stimulus), structure suggestion per format.
- Feeds: `rounds` tables get `games` ("2-1" or null); `standings` rows get `omw`, `gw`, `ogw` for 1v1 and omit
  `seats`; `info` gets `format` and `matchGames`. Keys for multiplayer unchanged.
- Landing copy (already in the mock): "Built for multiplayer. Open to every format."

## 8. Tests that pin it

- Pairer: no rematches over 5 rounds of 16; odd field gives one bye per round to the lowest unbye'd player;
  pair-down keeps groups even; last round pairs top-down; deterministic with the seed.
- Tiebreakers: MTR Appendix C worked examples (5-2-1 → .667; 1-3-0 → .25 → .33; bye excluded from OMW).
- Structure table and cut sizes; bracket pairing 1v8…4v5 then 1/8 vs 4/5 winners.
- Apply with games; feeds shape; standings columns; form lock; simulation gate unchanged for multiplayer.

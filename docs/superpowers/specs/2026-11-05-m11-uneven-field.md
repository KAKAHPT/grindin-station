# M11 — Uneven field: byes or pods of 3

**Date:** 2026-11-05. **Status:** draft for review. **Scope:** multiplayer tournaments (Swiss rounds). 1v1 and leagues are untouched.

## 1. Problem

When the field is not a multiple of 4, Grindin always splits the remainder into pods of 3 (and plays a pod of 5 with exactly 5 players). Organisers cannot choose byes instead, pods of 5 are not acceptable, and nothing stops the same player from landing in a pod of 3 (or on a bye) round after round.

## 2. Decisions (confirmed with the organiser)

| # | Decision | Value |
|---|----------|-------|
| D1 | The organiser picks, per tournament, how an uneven field is handled | `uneven_field` ∈ `pods_of_three` (default, current behaviour) \| `byes` |
| D2 | Pods of 5 | never, in either mode |
| D3 | `byes` mode with a remainder of 3 | one pod of 3 (three players play instead of sitting out) |
| D4 | Points for a bye | `event.points_bye` (existing field, 1v1 already uses it) |
| D5 | Repetition rule | nobody gets a second pod of 3 or a second bye while a legal swap exists with someone who has had fewer; otherwise the one with the fewest |
| D6 | Locked once the Swiss starts, like the other structure attributes | yes |

## 3. Pod shapes

`n` = active (non-dropped, non-waitlisted) participants of the round. `r = n % 4`.

| Mode | r = 0 | r = 1 | r = 2 | r = 3 |
|------|-------|-------|-------|-------|
| `pods_of_three` | all 4s | 4s and three 3s (`n ≥ 9`); `n = 5`: one 4 and **one bye** | 4s and two 3s (`n ≥ 6`) | 4s and one 3 |
| `byes` | all 4s | 4s and **one bye** | 4s and **two byes** | 4s and one 3 (D3) |

Rules that follow:
- `n = 5` is the only field where `pods_of_three` hands out a bye (5 does not split into 3s and 4s and pods of 5 are gone).
- The pods of 3 are the last tables (current behaviour); a bye is an `Advance` result in the `SwissRound` with no pod, exactly as 1v1 does it, worth `points_bye`. `number_of_byes`, standings, exports (`standings.csv` byes column, `rounds.csv` "bye" rows) and "my table" (`Play::TableState`) already handle it.
- Fields below 4 keep today's behaviour (whatever it is) — out of scope.

## 4. Who sits in the short pod or takes the bye

Definition: a player's **short count** = number of Swiss rounds of this event in which they sat in a pod of 3 **or** had a bye. One number covers both (an event normally only has one of them; `n = 5` is the exception).

### 4.1 Byes

Chosen before the pods are built, from the pairing order (`PlayerSorter#paired_players`, or `#random_players` in random mode), bottom up: the lowest-ordered player with the **lowest short count** takes the bye; with two byes, repeat on the remaining field. This mirrors `OneVOnePairer#bye_player` (lowest-ranked without a bye yet, else the last).

### 4.2 Pods of 3

After matching and after `RematchRepair`, a new pass `Tournaments::ShortPodRepair` swaps players between pods of 3 and pods of 4 while the number of players sitting in a pod of 3 for a repeated time strictly decreases:
- Walk the pods of 3 bottom up; for each candidate with `short_count > 0`, look at the pods of 4 nearest by table (same order as `RematchRepair#pods_by_distance`) for a player with a **lower** short count, within `max_point_gap` match points, whose swap does **not** increase the round's rematch pairs (`RematchRepair`'s count).
- The caller widens the gap with the same ladder as rematches (`CreatePodsJob#rematch_gaps`: 0, draw, one win, two wins, …, any), stopping once nobody in a pod of 3 is repeating or no gap helps. Random mode uses `[Float::INFINITY]` as it does for rematches.
- Swaps are capped like `RematchRepair` (`MAX_SWAPS_PER_POD`).
- Result: the players in the pods of 3 are those with the fewest short counts that the points structure allows; a repeat only happens when no legal swap exists (D5).

Rematch repair keeps priority: it runs first, and the short-pod pass never undoes it (a swap that adds a rematch is rejected).

## 5. Settings, pages and feeds

- `events.uneven_field` string, not null, default `"pods_of_three"`; `Event::UNEVEN_FIELDS = %w[pods_of_three byes]`; predicates `pods_of_three?` / `byes?`; validated by inclusion; in `Tournament::STRUCTURE_ATTRIBUTES` (locked after the Swiss starts, D6). 1v1 ignores it (always byes); like `pairing_mode`, `before_validation` normalises 1v1 to the default so the column never carries a meaningless value.
- **Settings** (organizer `_form`): a select "Uneven field" right after "Pairing", inside the same multiplayer-only block, disabled when locked, with a two-line help in the pairing-help style:
  - Pods of 3: "When the field is not a multiple of four, the last tables seat three players."
  - Byes: "Only pods of four; the one or two players left over get a bye worth the bye points (three left over still play a pod of three)."
  - The `points_bye` field keeps working for both modes; its label help gets one line: "Used for byes in 1v1 and when the uneven field is set to byes."
- **Overview** (organizer `show`): a row "Uneven field" under "Pairing".
- **Public About card** (`play_format_line`): append the mode name after the pairing name, multiplayer only ("… · Swiss pods · Byes · Top 4 · …").
- **Feeds::Info** (`app/models/feeds/info` or wherever `pairingMode` lives): `unevenField` string, nil for 1v1.
- i18n: `organizer.uneven_fields.{pods_of_three,byes}`, `organizer.uneven_help.{pods_of_three,byes}`, label `uneven_field` under the same activerecord attribute keys as `pairing_mode`; en + pt-PT (pt-PT: "Campo desigual", "Pods de 3", "Byes", tu-form help).
- Layout: existing M7 pieces only (`.field`, `form-help`, `ctable` rows). No new visual language.

## 6. Code removals

- `Event::LARGER_POD_SIZE` and the pod-of-5 branch in `UnevenPodGenerator` go away (D2), with the test asserting the constant. `empty_seat_counts` keeps seats 1..5 so historic seatings at seat 5 still load.
- `UnevenPodGenerator` becomes the single place that turns `(n, uneven_field)` into pod sizes plus a bye count (§3), with a table-driven test over n = 4..20 for both modes.

## 7. Simulation gate

`grindin:simulate` (`Tournaments::SeatSimulator`) gains the repetition measure: for a field of 13 (three pods of 3 per round) over 4 rounds, report the share of players who sat in a pod of 3 two or more times, with and without `ShortPodRepair`. Gate: with the repair the share must be ≤ the value measured when the rule lands (recorded in the notes file like the seat numbers), and never above the baseline without it. The simulator keeps skipping `RematchRepair`; the short-pod pass runs after its pairing step with the same gap ladder.

Note for the plan: the simulator builds pods without the database, so `ShortPodRepair` must accept plain candidate arrays plus a `short_counts` hash and a `rematch` predicate, the way `SeatAssigner` takes `seat_counts:`.

## 8. Out of scope

- Byes in leagues; leagues keep their own `pod_size`.
- A bye for a field of 3 or fewer.
- Changing how 1v1 picks its bye.
- Letting the organiser pick who gets the bye by hand (the result correction tools stay as they are).

## 9. Acceptance

1. Settings shows the new select for multiplayer tournaments, hidden for 1v1, locked after the Swiss starts; Overview and the public About card show the chosen mode.
2. `pods_of_three`: 13 players → 1×4 + 3×3; 6 → 2×3; 5 → 1×4 + 1 bye; never a pod of 5.
3. `byes`: 13 → 3×4 + 1 bye; 14 → 3×4 + 2 byes; 15 → 3×4 + 1×3; 5 → 1×4 + 1 bye.
4. A bye is an `Advance` in the Swiss round, worth `points_bye`, shown as a bye on the player's "my table", in standings and in the exports.
5. Over a 13-player, 4-round simulated Swiss, the share of players with two or more pods of 3 is lower with `ShortPodRepair` than without, and no swap of that pass adds a rematch.
6. Round 2 of a real 13-player tournament seats, in the pods of 3, only players who were not in a pod of 3 in round 1 (unit test on `CreatePodsJob`); with 13 players and 5 rounds, the 5th round must repeat someone and the test shows it picks the players with the fewest short counts.
7. 1v1 tournaments behave exactly as before (existing suite).

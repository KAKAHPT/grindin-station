# M8 — Multiplayer pairing modes (2026-11-05)

Owner's ask (backlog after M6, "like TopDeck"): a `pairing_mode` per multiplayer event, chosen in Settings:
**Swiss pods** (today's default), **Random pods** (ignore points every round), **Power pods** (strict top-down by
points, no spread). Seat fairness and rematch repair run in every mode; the simulation gate must pass per mode;
the organizer can change the mode until the swiss starts. Research: TopDeck names Swiss pods / True Swiss /
Power pods / Bubble pods / Random pods (`docs/superpowers/notes/2026-11-05-m10-export-research.md` §TopDeck).

Ruling: TopDeck's "True Swiss" is plain Swiss by record, which is what our Swiss pods already do outside the
round-2 spread; it adds nothing distinguishable, so it is not offered. "Bubble pods" (seated in standing order)
is a seating rule, which we never give up (seat fairness is the product), so it is not offered either.

Global constraint (owner, 2026-11-04 night): every page keeps the M7 design — the same cards, `card-title`
bands, `.field` inputs, `seg`/chips, topbar; no new visual language. Layouts are reviewed with the owner the
next morning.

## 1. Data

- `events.pairing_mode` string, not null, default `"swiss"`, values `Event::PAIRING_MODES = %w[swiss power random]`.
- Meaningful for `multiplayer` events only. 1v1 events keep `"swiss"` and `Tournaments::OneVOnePairer` ignores
  it. Leagues keep the default and never show the field.
- Locked with the structure: added to `Tournament::STRUCTURE_ATTRIBUTES`, so `structure_locked_after_start`
  refuses a change once the swiss has started (error `:locked`, message like the others).

## 2. Pairing behaviour (`Tournaments::CreatePodsJob`, multiplayer swiss rounds)

Common to all modes, unchanged: `UnevenPodGenerator` sizes the pods; `RematchRepair` swaps players between
pods while rematches decrease; `Pod#sit_participants!` → `SeatAssigner` (fair seats, seeded ties).

| Mode | Order fed to the matcher | Matcher per round | Rematch gaps |
|---|---|---|---|
| `swiss` | today's `PlayerSorter#paired_players` (ranking, each points group dealt by seat need) | today's `swiss_round_strategy`: round 2 spread (serpentine) when ≥ 3 rounds, otherwise top-down | today's escalating list (0, draw, win, 2 wins, …, any) |
| `power` | same ranking order | `SwissMatcher` (top-down) every round, never spread | same escalating list |
| `random` | the whole field shuffled with a seeded RNG (`Random.new(Digest::SHA256(event.seed, round.number)[0,8].hex)`), then dealt by seat need as **one** group (`PlayerSorter.deal(field, seat_counts)`) | `SwissMatcher` (top-down over that order) | `[Float::INFINITY]` only (points never matter) |

`Tournament#swiss_round_strategy(number, total)` becomes mode-aware: `:standard` for `power` and `random` in
every round; unchanged for `swiss`. `rounds_info` keeps its shape (`{ swiss_round: :standard | :spread | :forced }`).

Determinism: with the same event seed, players and history, every mode produces the same pods (tests assert
this for `random`).

## 3. Simulation gate

`Tournaments::SeatSimulator.new(players:, rounds:, rng:, seating:, mode: :swiss)` accepts `mode:` in
`%i[swiss power random]`; `random` shuffles the field each round and deals it as one group; `swiss` and `power`
keep today's top-down by points (the simulator never modelled the spread round, and still does not).
`grindin:simulate[n]` runs the fair seating for each mode and prints one table per mode; the gate (never-first ≤
0.017, spread≤1 ≥ 0.877) applies to each mode; the task fails if any mode fails. CI keeps `grindin:simulate[500]`.
Record the measured values in `docs/superpowers/notes/2026-11-05-m8-pairing-modes.md`.

## 4. Organizer and public surfaces

- Settings form (`organizer/tournaments/_form`, Structure section, multiplayer only via the existing
  format-fields Stimulus toggling): a `.field` select "Pairing" with options Swiss pods / Power pods / Random
  pods and a one-line help under it describing the chosen behaviour (three help strings, shown by the same
  Stimulus mechanism as the points defaults or as a single static help listing the three); `disabled` when the
  structure is locked, like `swiss_rounds_count`.
- Organizer tournament page (Overview tab): the structure card (where swiss rounds / cut are shown) gets a
  "Pairing" row with the mode name. Public event page (`/t/:slug`): the mode name appears in the event-header
  line next to the format/rounds information that is already there, multiplayer only.
- `Feeds::Info` adds `pairingMode: "swiss" | "random" | "power"` (multiplayer; `null` for 1v1).
- Copy in en/pt/es (`i18n_parity_test` keeps them key for key): names `Swiss pods` / `Power pods` / `Random
  pods`, helps: swiss "Pods by record; round 2 spreads the leaders across tables."; power "Strict top-down by
  standings every round, like a final round."; random "Records are ignored; every round is a random draw.".
  Portuguese / Spanish equivalents written by the implementer, reviewed by the task reviewer.

## 5. Tests

- Model: default `swiss`, inclusion, lock after swiss, 1v1 ignores.
- `CreatePodsJobTest`: power never spreads in round 2 (top 4 by points share pod 1 on a 20-player spread-shaped
  history); random ignores points (with 16 players after 1 round where 4 won, the 4 winners are not all in pod
  1 across the seeded draw, and the pods for a given seed are identical on a second run); random has 0
  rematches after 16 draws for 3 rounds (repair still runs); every mode seats every player once with
  `assigned_by: "fair"`.
- Simulator test: `mode: :random` runs and reports; task gate per mode.
- Controller: organizer can set the mode before the swiss, gets `:locked` after; strong params include it.
- Feed test: `pairingMode` present.

## Out of scope

Bye modes, draw modes, bubble pods, cut-aware last-round rules (TopDeck does not document any).

# Seat simulation: the targets are not met (Task 11)

`bin/rails "grindin:simulate[2000]"`, `SIM_SEED=42`: 16–140 players, 4–7 rounds, 30 % of pods draw, otherwise one
random winner (7/1/0). Pods of 4 filled by points, leftovers as pods of 3 at the bottom, seats by
`Tournaments::SeatAssigner`. No rematch repair. Targets: mean `never_first_rate` <= 0.01 and mean
`max_spread_le1_rate` >= 0.99 (per player, max − min over seats 1..4).

## A. Current algorithm (random order among equal points; what `PlayerSorter` does today)

```
rounds        n  never_first    spread<=1  worst avg    max
4           514       0.0726       0.6284       2.00      2
5           545       0.0075       0.9216       1.98      3
6           458       0.0002       0.9735       1.78      3
7           483       0.0000       0.9078       2.37      3
all        2000       0.0208       0.8548       2.04      3
FAIL (never_first_rate 0.0208 must be <= 0.01, max_spread_le1_rate 0.8548 must be >= 0.99)
```

`SIM_SEED=7` gives the same picture: 0.0217 / 0.8524.

## B. Refinement from the spec, as written (equal points: fewest seat-1s first, then random)

```
rounds        n  never_first    spread<=1  worst avg    max
4           503       0.1960       0.4750       2.46      3
5           492       0.0903       0.8123       2.68      4
6           523       0.0300       0.8893       2.61      4
7           482       0.0067       0.8185       2.76      4
all        2000       0.0810       0.7491       2.63      4
FAIL (never_first_rate 0.081 must be <= 0.01, max_spread_le1_rate 0.7491 must be >= 0.99)
```

It makes things worse. Pods are filled by adjacency, so sorting the seat-1 debtors to the front of their
points group puts them side by side, in the same pods. Only one of them can take seat 1 in each pod.
This was not applied to `PlayerSorter`.

## C. Experiment: debtors dealt one per pod (scratch only, not committed)

Within each equal-points group, the debtors are dealt across that group's pods: one per pod, then a second
round, and so on.

```
rounds        n  never_first    spread<=1  worst avg    max
4           509       0.0384       0.6761       2.00      2
5           502       0.0016       0.9340       1.95      3
6           491       0.0000       0.9719       1.73      3
7           498       0.0000       0.9224       2.37      3
all        2000       0.0102       0.8748       2.01      3
FAIL (never_first_rate 0.0102 must be <= 0.01, max_spread_le1_rate 0.8748 must be >= 0.99)
```

`never_first` reaches the limit (0.0102 against 0.01), but only because the 5–7-round tournaments bring
the mean down. At 4 rounds it is still 3.8 %.

## The brief's two unit tests, per variant

| variant | 40 players, 4 rounds, mean never_first (≤ 0.01) | 64 players, 5 rounds, spread≤1 (≥ 0.99) |
|---|---|---|
| A current | 0.0835 | 0.9688 |
| B spec refinement | 0.1695 | 0.8594 |
| C dealt one per pod | 0.0535 | 0.9531 |

## Reading

- **`never_first` at 4 rounds:** this is close to a perfect-matching problem. With 40 players there are
  exactly 40 seat-1 slots in 4 rounds, so any pod with two debtors leaves someone out. Adjacency by points
  limits which players can share a pod, and the cost function cannot fix composition.
- **`spread<=1` at 0.99:** out of reach for any choice made one pod at a time. After 4 rounds,
  spread ≤ 1 over seats 1..4 means a perfect rotation (1·1·1·1). After 7 rounds it means exactly
  2·2·2·1. Even the best variant gets 0.68 at 4 rounds and 0.92 at 7 rounds.
- **Which reading of the spec?** §5.3 says "≤ 1 em ≥ 99 % dos torneios" (99 % of tournaments). The brief
  uses the fraction of players instead. The per-tournament reading is stricter still.

## Options for the decision

1. Keep the targets and change composition (seats would have to factor into pairing). That is a bigger
   change than this task.
2. Adopt C in `PlayerSorter`. It reorders only within equal points and improves both rates, but it still
   fails the brief's thresholds and tests.
3. Set the gate to what A or C actually achieves, and measure the targets as a trend instead.
   This is a call for Kakah and the controller, not for the implementer.

---

# Fix round 1 (decision taken): need-aware dealing, random baseline, regression gate

The harness changed slightly: each tournament now gets its own seed, so the fair run and the random run see the
same players, rounds and results. A and C were measured again under the new harness. Command:
`bin/rails "grindin:simulate[2000]"`, `SIM_SEED=42`.

## D · need-aware dealing (adopted)

Within each group of equal match points:
1. Find each player's needed seat: their least-used of seats 1..4 (lowest seat on ties).
2. Sort the group by needed seat, then by fewest seat-1s, keeping the incoming order otherwise.
3. Deal player k to pod k mod P, where P = ceil(size / 4).

This is `Tournaments::PlayerSorter.deal`. The simulator calls it, and so does real swiss pairing through
`PlayerSorter#paired_players` (used by `CreatePodsJob`). The order between points groups does not change.

```
rounds   seating      n  never_first    spread<=1  worst avg    max
4        fair       526       0.0404       0.7433       2.00      2
4        random     526       0.3046       0.0941       3.61      4
5        fair       511       0.0022       0.9573       1.84      3
5        random     511       0.2273       0.2333       4.18      5
6        fair       463       0.0000       0.9739       1.72      3
6        random     463       0.1701       0.2547       4.81      6
7        fair       500       0.0000       0.9279       2.36      3
7        random     500       0.1288       0.1486       5.28      7
all      fair      2000       0.0112       0.8975       1.98      3
all      random    2000       0.2098       0.1805       4.45      7
```

## A, C and D side by side (fair seating; same harness)

| variant | never_first (all) | spread≤1 (all) | never_first at 4 rounds | spread≤1 at 4 rounds |
|---|---|---|---|---|
| A: ties in random order | 0.0219 | 0.8535 | 0.0753 | 0.6268 |
| C: debtors one per pod | 0.0105 | 0.8725 | 0.0380 | 0.6707 |
| **D: need-aware dealing** | **0.0112** | **0.8975** | 0.0404 | 0.7433 |

D roughly halves never_first compared with A, and it improves spread≤1 by 4.4 points. C is about equal on
never_first but 2.5 points lower on spread, so D was kept.

## Baseline random (seats shuffled in each pod, as TopDeck-style seating does)

never_first 0.2098 (21 % of players never sit in seat 1), spread≤1 0.1805, worst spread up to 7.
Our seating: 0.0112 / 0.8975, worst spread at most 3.

## Gate chosen (regression gate, not the target)

- `grindin:simulate` fails if the mean never_first_rate > **0.017**, or the mean max_spread_le1_rate < **0.877**.
  These are D's measured levels (0.0112 / 0.8975) with a margin of +0.005 / −0.02, rounded in the safe direction.
  CI runs `grindin:simulate[500]` (500 tournaments: 0.0117 / 0.8933; SIM_SEED=1: 0.0112 / 0.9013;
  SIM_SEED=7: 0.0105 / 0.8997).
- The unit tests use the same margins:
  - 40 players, 4 rounds, mean of 50 seeds: measured 0.057, asserted ≤ 0.062.
  - 64 players, 5 rounds, seed 3: measured 0.9688, asserted ≥ 0.948.
- The aspirational targets in spec §5.3 (nobody without seat 1 at ≥ 4 rounds; spread ≤ 1 for ≥ 99 %) still
  stand. They are not met.

## Caveat: real ties are by points, not rank_score

`rank_score` includes the seeded `tiebreak_salt`, so in practice two players never tie on it. Dealing only
within equal rank_score would change nothing. So `paired_players` groups by **match points**. The simulator
models it the same way, with tiebreakers as a random order.
`sorted_players` (the full ranking) is unchanged, because top cut uses it to decide who advances.

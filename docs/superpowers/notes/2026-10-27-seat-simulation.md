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

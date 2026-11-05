# M11: short-pod spread (uneven field)

`bin/rails "grindin:simulate[2000]"`, SIM_SEED=42, 2000 tournaments of 13 players (1 pod of 4 + 3 pods of 3 every
round), 4 rounds, swiss. `Tournaments::ShortPodRepair` on (ladder: same points, a draw, one win; rematches not
modelled) vs off (the baseline). Short count = rounds a player sat in a pod of 3 (the simulator has no byes).

| short_repair | short_spread (max - min) | short_max |
|---|---|---|
| true | 1.4630 | 3.3550 |
| false | 3.4645 | 4.0000 |

- 9 of 13 players sit short every round (36 short seats over 4 rounds, 2.77 per player), so "sat short two or more
  times" cannot fall: an even spread gives everyone 2 or 3 (ruling R7). The gate measures the spread instead.
- Gate: repaired mean spread <= the baseline mean spread and <= the recorded level 1.463 + 0.1. The task exits 1 if it fails.
- The repair is on by default in every mode, so the seat numbers move slightly (2000 runs, fair seating):
  swiss/power 0.0116 / 0.9023 (M8: 0.0112 / 0.8975), random 0.0005 / 0.9612 (M8: 0.0000 / 0.9685); all within
  the seat gate (never_first <= 0.017, spread<=1 >= 0.877).
- CI keeps calling `bin/rails "grindin:simulate[500]"`.

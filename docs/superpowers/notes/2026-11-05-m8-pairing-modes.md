# M8: seat fairness per pairing mode

`bin/rails "grindin:simulate[2000]"`, SIM_SEED=42, 2000 tournaments (16-140 players, 4-7 rounds). Fair seating
(Tournaments::SeatAssigner) vs the random baseline.

| mode | seating | never_first | spread<=1 | worst avg | worst max |
|---|---|---|---|---|---|
| swiss | fair | 0.0112 | 0.8975 | 1.98 | 3 |
| swiss | random | 0.2098 | 0.1805 | 4.45 | 7 |
| power | fair | 0.0112 | 0.8975 | 1.98 | 3 |
| power | random | 0.2098 | 0.1805 | 4.45 | 7 |
| random | fair | 0.0000 | 0.9685 | 1.40 | 3 |
| random | random | 0.2104 | 0.1848 | 4.49 | 7 |

- `power` is identical to `swiss` in the simulator: it never modelled the spread round, so the numbers are the same by construction.
- `random` deals the whole field as one group by seat need every round, so fairness is better than swiss (no equal-points group boundaries).
- Gate (fair seating, every mode): never_first <= 0.017 and spread<=1 >= 0.877. All three modes pass; the task exits 1 if any fails.
- CI keeps calling `bin/rails "grindin:simulate[500]"` unchanged.

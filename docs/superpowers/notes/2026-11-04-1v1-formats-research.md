# 1v1 formats: how the incumbents pair and rank (research, 2026-11-04)

Goal (spec: `docs/superpowers/specs/2026-11-04-1v1-format-design.md`): let an organiser choose the event **format** (multiplayer pods, as today, or **1v1**) so Grindin Station
can serve stores and communities that run Standard/Modern/Pioneer/Limited, Pokémon-style or any two-player
game. This note records what the reference systems actually do, with sources, so the spec argues from facts.

## 1. Wizards of the Coast: Magic Tournament Rules (MTR, 30 Jun 2025)

Official text, read from the PDF (`media.wizards.com/.../MTG_MTR_2025_Jun 30_EN.pdf`).

- **10.4 Pairing algorithm.** "Unless otherwise announced, tournaments are assumed to follow the Swiss pairing
  algorithm." The MTR does **not** describe the algorithm's internals; it only fixes the playoff pairing:
  8-player bracket 1v8, 2v7, 3v6, 4v5, with 1/8 and 4/5 winners meeting; 4-player bracket 1v4, 2v3. Playoff
  seeding by final Swiss standings.
- **10.2 Number of rounds.** Minimum 3 rounds for individual events; the number (or the stopping rule) must be
  announced before round 1 and cannot change.
- **Appendix E, recommended Swiss rounds (required for Premier events):**

  | Players | Swiss rounds | Playoff |
  |---|---|---|
  | 5–8 | none, 3 single-elimination rounds | none |
  | 9–16 | 5 (4 if Limited with draft playoff) | Top 4 (Top 8 if Limited with draft playoff) |
  | 17–32 | 5 | Top 8 |
  | 33–64 | 6 | Top 8 |
  | 65–128 | 7 | Top 8 |
  | 129–226 | 8 | Top 8 |
  | 227–409 | 9 | Top 8 |
  | 410+ | 10 | Top 8 |

- **Appendix C, tiebreakers (order: match points, OMW%, GW%, OGW%):**
  - Match points 3 / 1 / 0 (win / draw / loss). Game points 3 / 1 / 0 per game; unfinished games are draws.
  - Match-win % = match points ÷ (3 × rounds played), **floored at 0.33**. Game-win % likewise, floored at 0.33.
  - OMW% = average of each opponent's match-win % (each floored). OGW% = average of opponents' game-win %.
  - **Byes:** a bye is a 2–0 win (3 match points, 6 game points) and is **ignored** when computing the
    player's OMW% and OGW%.
  - "Not all of these tiebreakers may be used in formats with single-game matches."
- **Swiss mechanics in practice** (judge guidance, not MTR text): pair within match-point groups, random inside
  the group, pair the odd player down to the next group, the bye goes to the lowest-ranked player who has not
  had one, and two players are "almost never" paired twice in the Swiss. EventLink (WotC's own software)
  added "power pairings" in 2021 so the last round pairs top tables like Premier Play. Sources:
  [MTR Appendix E](https://blogs.magicjudges.org/rules/mtr-appendix-e/),
  [MTR Appendix C](https://blogs.magicjudges.org/rules/mtr-appendix-c/),
  [MTR tiebreaker order](https://blogs.magicjudges.org/rules/?p=251),
  [judges on repeat pairings](https://apps.magicjudges.org/forum/post/50084),
  [EventLink power pairings](https://wpn.wizards.com/en/news/eventlink-release-notes-september-28-2021),
  [bye handling in Companion](https://feedback.wizards.com/forums/929932-companion-feedback/suggestions/46970809-inquiry-about-omp-and-ogp-calculation-in-the-swiss).

## 2. Melee.gg

- Tiebreakers identical to the MTR: match points (3/1/0, bye = win), OMW%, player game-win % ("TGW"), OGW%,
  floors at 33 %. Source: [Understanding Melee's Swiss, Top Cut Pairings and Standings](https://help.melee.gg/docs/understanding-melees-swiss-top-cut-pairings-and-standings/).
- Match types are a per-phase "Matching Method": Best-of-3 (default), **Two-Game Matches** (exactly two games,
  draws disabled; cannot be mixed with Bo3 because the tiebreakers differ). Source: [Two-Game Matches](https://help.melee.gg/docs/two-game-matches/).
- Byes are assigned automatically; staff can override through "Edit Match-ups". Game-specific tiebreaker sets
  exist (e.g. Star Wars: Unlimited uses match wins, OMW, TGW only). Source: [SWU tiebreakers](https://help.melee.gg/docs/star-wars-unlimited-tiebreakers/).

## 3. TopDeck.gg

- 1v1 is supported ("Swiss pairings automatically match players with similar records"; scoring, round structure
  and rules configurable per game type) but TopDeck publishes **no** 1v1 tiebreaker or pairing document; its
  help centre is about Commander pods (Swiss Pods / True Swiss / Power Pods, Top 4/10/13/16/40/64).
  Sources: [Getting started](https://topdeck.gg/help/getting-started),
  [Running a Commander tournament](https://topdeck.gg/help/running-commander-tournament).

## 4. start.gg (reference for the algorithm itself)

- Round 1 by seed (top half vs bottom half; unseeded by entry time). Then sort by points, group by points,
  pair inside the group (seeds as secondary preference), **odd player pairs down** to the next group, a group
  that cannot be paired without rematches **merges** with the next; maximum bipartite matching; rematches only
  if no rematch-free pairing exists at all (rare at the recommended round count). Bye added before grouping
  when the count is odd. Tiebreakers: head-to-head, then strength of schedule.
  Source: [start.gg Swiss algorithm](https://help.start.gg/en/articles/13813717-start-gg-s-swiss-algorithm-and-additional-swiss-info).

## 5. Other games (for the "every format" promise)

- **Pokémon TCG** and most TCGs: the same Magic family (OMW%-style "resistance", floored). Battlefy's default
  Swiss tiebreak set is OMW%, GW%, then opponents' opponents' MW% (OOMW%), floor 0.33.
  Source: [Battlefy Swiss tiebreakers](https://help.battlefy.com/en/articles/3367583-swiss-tie-breaker-formats).
- **Flesh and Blood**: draws are worth 0 match points but rank above losses; primary tiebreak "cumulative
  match points". Source: [FaB pairings and tiebreaker policy](https://legacy.fabtcg.com/en/resources/rules-and-policy-center/pairings-and-tiebreaker-policy/).
- **Chess-style** (Buchholz, Sonneborn–Berger) is what esports and board-game platforms use; not needed for v1.

## 6. What this means for Grindin Station

1. A **format** on the event: `multiplayer` (pods of 3–5, seat fairness, cEDH tiebreakers; today's behaviour,
   unchanged) or `one_v_one` (tables of 2).
2. 1v1 needs **game scores** per match (2-0, 2-1, 1-1-1 …): the result of a table becomes "winner + games", not
   just Win/Draw per participant. Best-of-3 by default; "two-game matches" and "single game" are options whose
   tiebreakers drop GW%-based steps (MTR: "may not be used in formats with single-game matches").
3. **Tiebreakers per format**: 1v1 = match points (3/1/0), OMW% (floor 0.33, byes ignored), GW%, OGW%,
   then the seed draw. Multiplayer keeps 7/1/0 and the cEDH set.
4. **Pairing per format**: 1v1 = Swiss by match-point groups, random inside, pair-down, no rematches (repair
   exactly like today's `RematchRepair`), bye to the lowest-ranked player without one; last round "power
   pairing" is the same as plain Swiss when groups are paired top-down inside (keep simple: top-down order
   inside the group instead of random for the final round, as EventLink does).
5. **Structure suggestion per format**: 1v1 uses Appendix E (5–8 players → single elimination only; 9–16 → 5
   rounds + Top 4; …); multiplayer keeps `Tournaments::Structure.suggested`.
6. **Top cut**: 1v1 bracket 1v8, 2v7, 3v6, 4v5 (and 1v4, 2v3), winners advance; single-elimination tables of 2.
7. **Seats**: irrelevant for 1v1 (play/draw by die roll); no seat columns, no seat fairness, no "Seats 1·2·3·4"
   in standings or feeds; the "fair seats" promise applies to multiplayer, which the landing already says.
8. The **OBS feed** keeps the same keys; `players` has 2 entries per table and `seats` is absent for 1v1.

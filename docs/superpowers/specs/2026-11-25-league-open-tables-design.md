# League "open tables" mode — design

Date: 2026-11-25. Status: approved by the owner on 2026-11-25. Module `leagues` stays OFF in `config/features.yml`
until the owner has tested this on a local preview and says so.

## Intent and why

The owner (cEDH PT) runs leagues where players arrange their own games, mostly online, over weeks. Today a
league in Grindin Station can only get a pod when the organizer clicks "Create pick-up pod" and the system picks
the players. The owner calls player-opened tables "the most used league mode": it must exist and be the default
for a new league. The league settings are to be rebuilt around it.

## What the owner decided (binding)

**Opening and filling a table**
- On the public page of a running league there is a tab where an enrolled player opens a table. Other enrolled
  players see the open tables and join one.
- A table closes by itself when the 4th player joins. Always 4, never 3 or 5.
- While it is not full: whoever joined has a **Leave** button; whoever opened it has a **Close table** button
  (frees everyone in it); a table open for 2 hours without filling closes by itself.
- A player is never in more than one table at a time: with a table waiting, or a full table without a confirmed
  result or an approved cancellation, they cannot open or join another.
- No room link (SpellTable / Discord) for now.

**After the table is full**
- It becomes a pod that counts for the league. Nobody can leave.
- The pod shows in `/my-events` for each of its players, under the league ("my pods"), with an optional
  **Open clock** button: players mostly play online and time the game elsewhere.
- **Submit result**: the same flow as tournaments (one player reports, the others confirm or contest).
- **Cancel table**: opens a dialog where a reason is mandatory. The request goes to the organizer, who approves
  (the table disappears, counts for nothing, the four are free) or refuses (the table stays and must be
  reported). While the request is pending the four stay locked to that table.

**Scoring (league settings)**
- Starting points: set by the organizer.
- Wager percentage: set by the organizer. At each table every player stakes that percentage of the points they
  hold; the single winner takes the pot.
- Draw rule, chosen by the organizer: the pot is **split equally** among the four, or the stakes are **lost**.

**Calendar and end**
- The organizer sets the start and the end when creating the league, can extend the end as often as wanted, and
  can reopen a closed league.
- When the organizer closes the league no table can be opened or joined; waiting tables are voided; full tables
  that already started play to the end. The league is really closed when the last result is confirmed (or the
  last cancellation decided).
- Only then can the organizer advance to the **top 16** and then the **final**, "exactly as in tournaments".

## Goals

1. A player can open, join, leave and close tables, report and confirm, with no organizer action.
2. The organizer can run the whole league from the site: start, extend, close, reopen, decide cancellations,
   fix a result, make the cut, finish.
3. New leagues default to this mode. The league form is rebuilt in the current design, in en/pt/es.
4. The wager scoring is correct and explainable to a player.

## Non-goals

- Turning the `leagues` switch on in production (separate decision after the owner's test).
- Room links; chat between players; push or e-mail per table.
- The half-built "scheduled" league mode: not fixed here and not offered in the form.
- Circuit fixes (points counted twice on reopen): separate work, but see "Constraints".
- Money: the wager is league points only. Players never pay through the site.

## Anti-goals

- Any change in how tournaments behave. Tournaments are live in production; `Pod`, `Results::*`, standings and
  exports must behave the same for them. A waiting table must never be read as a pod by any existing code.
- A player stuck with no way out (every waiting state has an exit: leave, close, the 2 h timeout, or the
  organizer).

## Constraints (from the code today)

- `League < Event` (STI). `play_mode` enum is `scheduled: 0, pickup: 1`, column default 0. The form
  (`app/views/organizer/leagues/_form.html.erb`) is English-only, old style, and has no field for the state or
  the mode: today a league cannot be moved to `play` from the site.
- `Leagues::CreatePickupPodJob` puts pick-up pods in one unpublished `SwissRound` with `is_play_round: true`.
- Player pages live under `/t/:slug` (`Play::BaseController`): `current_round` is the latest published round
  and `current_pod` the player's pod in it. That assumes one pod per player per round, which a league play
  round breaks (many pods per player over time).
- Reporting is `Play::ReportsController` + `Results::Report / Confirm / Contest / Timeout`; it reads
  `events.result_confirmation` and `confirmation_timeout_minutes`.
- `Events::SubmitResultJob` runs `Scoring::PointWager#recalculate_all!` for a league in `play`. Today it starts
  everyone at a constant 1000, averages a forward and a reverse pass, and on an all-draw sets each score to
  their share of the pot (a bug: it wipes the rest of their points).
- The cut lives in `Tournament` (`top_cut_size`, `Tournaments::TopCut`, state `single_elimination`, "Make
  cut"). `League#rounds_info` hard-codes a final of the top 3. `top_cut_size` is a column on `events`.
- `Leagues::FinishLeagueJob` awards circuit points; `Circuits::CalculatePoints` adds with `+=`, so a reopened
  and re-finished league would count twice. Reopen must not double-count.
- The clock pages (`Play::TimersController`) are per event round, not per pod.
- A paused module's routes go inside `constraints(Features.constraint(:leagues))`; tests run with everything on.

## Approaches

- **A (chosen) — the open table is its own record; it becomes a `Pod` when the 4th player joins.** The waiting
  room is separate; from then on the pod uses what tournaments already have. Waiting tables can never touch
  standings and tournament code stays as it is. Chosen because the anti-goal is the main risk.
- **B — give `Pod` a "waiting" state with partial seatings.** Fewer new pieces, but every reader of pods
  (standings, exports, prints, wager, live screens) would have to learn to skip incomplete pods; one miss breaks
  tournaments in production.
- **C — a separate match system for leagues.** Would rebuild reporting and confirmation that already work.

The owner left the how to the builder; A is the builder's pick.

## Design

### Data

- `league_tables` (name free): league, opener (event participant), `state` waiting | filled | closed | expired,
  `filled_at`, `pod_id` once filled. Members: a join table of event participants (max 4, one waiting table per
  participant per league enforced in the database, e.g. a partial unique index).
- Cancellation request, on the pod or its own table (builder's choice): requester, reason (required), state
  pending | approved | refused, decided by, decided at. One pending request per pod.
- `events`: `starting_points` (integer, default 1000), `draw_rule` (`split` | `lost`, default `split`),
  optional `max_games_per_week` and `max_games_vs_same_opponent` (both null = no limit). `wager_percentage`
  and `top_cut_size` exist.
- `play_mode`: add `open_tables` and make it the default for a **new league** (not by changing the column
  default, which tournaments share). Existing rows keep their value.
- League state: a way to tell "closing" (organizer closed, pods still to finish) from "closed, ready for the
  cut". Builder's choice between a new enum value and a timestamp; the existing integer values must not move.

### Player flow

- League page (`/leagues/:id`, and its `/t/:slug` equivalent): a **Tables** tab, visible to everyone, actions
  for enrolled players only while the league is in play and not closing.
  - "Open a table" (disabled with the reason when the player is already in a table or over a limit).
  - Waiting tables, oldest first: who is in (names open the profile), seats left, time left of the 2 h, and
    Join / Leave / Close table as applies.
  - "In play": the full tables without a confirmed result. "My table" pinned on top.
  - The list updates live (Turbo stream), like the tournament pages.
- 4th join: in one transaction, create the pod in the league's play round, seat the four, mark the table
  filled. Two players racing for the last seat: one gets it, the other sees "this table just filled".
- Seat order (who plays first matters in cEDH): assigned by the existing fair seat assigner over each player's
  seat history in this league, shown on the pod.
- The four get an in-app notification ("your table is full").
- `/my-events`: under a running league ticket, the player's current pod with Submit result, Cancel table and
  Open clock, and a link to the Tables tab when they have none.
- Open clock: a per-pod clock any of the four can start (stores a start time on the pod; uses
  `events.round_minutes`; no automatic consequence when it runs out).
- 2 h timeout: counted from when the table was opened, for any waiting table (1, 2 or 3 players), by a
  recurring job; the check is also made on read so a stale table is never joinable.

### Results and scoring

- Reporting, confirming and contesting reuse `Results::*`. For leagues the default is that the other players
  confirm (`result_confirmation`), with the existing timeout sending the pod to the organizer's review.
- `Scoring::PointWager` is rewritten to one chronological pass (order: when each pod's result became final),
  starting from `starting_points`:
  - one winner: each player stakes `wager_percentage` % of their current points; the winner receives the pot;
  - draw, `split`: the pot is divided equally among the four;
  - draw, `lost`: each player loses their stake and nobody receives it.
  It is still a full recalculation after every final result, correction or approved cancellation.
- A cancelled pod is removed from the scoring entirely.
- Standings: league score, then number of wins, then fewer games played, then registration time.

### Organizer flow

- League page in organizer mode gets the state buttons: Open registration, Start league, Close league, Reopen,
  Make cut, plus "Extend" (changes the end date). All audited like tournament state changes.
- After the end date no table can be opened; the league stays in play until the organizer extends or closes.
- Close league: voids waiting tables; shows "N tables still to finish" with each one; the organizer can enter
  a result or cancel any of them. When none is left the league becomes closed and "Make cut" appears.
- Cancellation requests: a list with the reason and Approve / Refuse; the organizer gets an in-app
  notification for each request and the four players one for the decision.
- Cut: `top_cut_size` setting (default 16; 4 allowed; none = the top score wins), run with the tournament cut
  machinery (16 → four pods → final of the four winners). Cut pods do not move league scores. The final's
  winner is the league champion; final positions follow the cut, then the league standings.
- Reopen: only before the cut starts; puts the league back in play. Finishing again must not double circuit
  points (recompute that league's contribution instead of adding).
- Registration stays open while the league is in play: a late player starts with `starting_points`.
- League form, rebuilt: name, cover, dates, min/max players, mode (open tables — default; organizer pick-up),
  starting points, wager %, draw rule, cut size, the two optional limits, circuit, prizes, description, price
  (information only).

### Left to the builder

Names of tables and classes, where the cancellation request lives, how "closing" is stored, how the tournament
cut code is shared with `League` without changing `Tournament`'s behaviour, and how `Play::BaseController`
finds a league player's current pod.

## Calls made by the builder, not by the owner

1. The 2 h timeout applies to tables with 2 or 3 players too, counted from the opening.
2. Seat order by the fair seat assigner when the table fills.
3. Scoring in one chronological pass (the forward/reverse average is dropped: a player cannot follow it).
4. No game limits by default; two optional limits in the settings.
5. Registration stays open during play.
6. Cut size is a setting (default 16); cut games do not move league scores.
7. After the end date no new tables, but the league does not close by itself.
8. Reopen only before the cut starts.
9. The form offers "open tables" and "organizer pick-up"; "scheduled" is not offered.
10. The per-pod clock has no consequence when it runs out.
11. Field smaller than the cut: "Make cut" offers the largest cut that fits (16, else 4, else no cut); it never
    blocks the organizer.
12. A qualified player absent for the cut: before starting the cut the organizer can drop them and the next in
    the standings steps in. No confirm-attendance step.
13. A finished league cannot be reopened. Reopen is only closing/closed → play, before the cut starts; the
    circuit recompute is defensive.
14. With no cut, the league finishes on an organizer "Finish" click once every table is settled, not by itself.
15. A player dropped from the league keeps their past results in the scoring (removing them would change other
    players' points). If they sit at an unfinished table, it stays and shows in the organizer's list to decide.

## Decided by the owner after the review (2026-11-25, binding)

- **Minimum games for the cut**: a league setting chosen by the organizer (`events.min_games_for_cut`), default
  **10**. Only players with at least that many settled league games are eligible for the cut; the others stay
  in the standings, marked as not qualified. 0 turns the rule off.
- **Confirming a league result**: one of the other three players confirming is enough; the window is **24
  hours**; when it ends with no contest the reported result is **accepted by itself** (leagues only —
  tournaments keep never auto-accepting). A contest still sends the pod to the organizer.
- **A full table nobody reports**: after **7 days** without a result the organizer gets a notification and the
  table is flagged in their list to decide (enter a result or cancel). It never cancels by itself.

## Testing

- Model and service tests for the table lifecycle (open, join, leave, close, expire, fill, the one-table rule,
  the race for the last seat) and for the scoring (winner, both draw rules, cancellation, correction).
- System tests for the player flow on a phone-sized browser and the organizer's close → cut → finish.
- `test/integration/launch_phase_test.rb` keeps every league route 404 with the switch off.
- The full tournament suite stays green with no test changed.

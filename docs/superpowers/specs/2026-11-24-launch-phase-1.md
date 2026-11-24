# Launch phase 1: the cEDH tournament only

Decided by the owner on 2026-11-24. Grindin Station goes public in phases. Phase 1 puts only the cEDH tournament
online, to be tested from start to finish; everything else is paused but intact.

## On

- The whole cEDH tournament: registration, check-in, Swiss in pods of 4 (and 3), top cut with the bracket, public
  pairings and standings, results reported at the table, timer, judge calls, infractions.
- Organizer mode, exports, the admin area.
- Accounts, sign-in and the player profile. Names in pairings and standings open the profile (owner's decision).
- The public API the cEDH PT stream kit reads.
- The organizers' waiting list on the landing (it collects contacts, it gives no access).

## Paused

| Switch       | What it pauses                                                                  |
|--------------|---------------------------------------------------------------------------------|
| `feed`       | `/feed`, posts, likes, reports, Follow, follower counts, the account's feed setting, `/admin/feed` |
| `leagues`    | `/leagues`, `/organizer/leagues`, leagues in `/events`                          |
| `circuits`   | `/circuits`, `/organizer/circuits`, `/admin/circuits`, featured circuits on the landing |
| `rankings`   | `/rankings`, `/admin/invitational`                                              |
| `teams`      | the account's Team card, `/teams`, `/team_memberships`, the team tag on profiles |
| `one_v_one`  | 1v1 tournaments: the Format select offers Commander / cEDH only and the server forces it; no format filters |
| `fairness`   | `/fairness` and the links to it                                                 |
| `organizers` | `/organizers`, `/o/:handle`, the organizer's About editor                       |

Only the owner (cEDH PT) creates tournaments: the organizer role is given by an admin only, and nobody else is
approved during phase 1.

## How

- `config/features.yml`: one boolean per module. `shared` is what development and production run; `test` turns
  everything on so the paused code keeps being tested.
- `Features.on?(:name)` (`app/models/features.rb`) in views, helpers and controllers; an unknown name raises.
- `constraints(Features.constraint(:name))` around a module's routes: while it is off they do not match, so every
  address answers 404, for everyone. Path helpers still exist, so no view breaks.
- Background data is left alone: a finished tournament still writes its result post and ranking rows, so
  nothing is missing when a module comes back. The rehearsal tournament must be deleted afterwards for that reason.
- To bring a module back: set its line to `true`, deploy.
- `test/integration/launch_phase_test.rb` runs the launch set: every paused route is 404 (visitor and admin),
  the tournament pages open and link to nothing paused, names link to profiles, new tournaments are cEDH.

## Landing in phase 1

Menu: Events only. The hero says "Built for cEDH". The "Why it is fair" explanation stays (it is the reason to use
Grindin for cEDH), without the button to the seat report. No featured circuits, no format filter.

## Rehearsal tournament (before opening to the public)

1. The owner creates the tournament and opens registration.
2. Players register and check in, with a count that forces a pod of 3 (for example 11).
3. Swiss rounds: pairings, timer, results reported at the table, one draw, one judge call, one infraction, one drop.
4. Top cut to the end; the tournament finishes.
5. Export the results; check profiles and standings.
6. Delete the rehearsal tournament.

Whatever fails is fixed before opening.

## Needed from the owner before the rehearsal

VPS, domain and deploy secrets; SMTP (without it nobody can confirm an account); the admin flag on the owner's
account (`bin/rails "grindin:admin[email]"`) and its organizer approval.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- **Start development server**: `bin/dev` (uses Procfile.dev to run Rails server and Tailwind CSS watcher)
- **Rails console**: `bin/rails console`
- **Database commands**: 
  - `bin/rails db:migrate`
  - `bin/rails db:seed`
  - `bin/rails db:reset`
- **Testing**: 
  - `bin/rails test` (for unit tests)
  - `bin/rails test:system` (for system tests)
- **Seat fairness simulation**: `bin/rails "grindin:simulate[2000]"` (fails if seat fairness regresses; CI runs it with 500)
- **Code quality**:
  - `bin/rubocop` (Ruby linting with Rails Omakase configuration)
  - `bin/brakeman` (security analysis)
- **Asset compilation**: `bin/rails tailwindcss:build`
- **Backups** (run on the VPS): `bin/backup` (pg_dump of the primary DB, `umask 077`, keeps 14, optional rclone), `bin/restore <file>` (hands the tables back to `grindin_app`)
- **Docker/deploy**: `bin/docker-smoke` (builds the image and boots production; prints "docker not available" without Docker), `bin/kamal` (needs `GS_VPS_HOST`/`GS_DOMAIN` exported; CI normally deploys)

## Architecture Overview

This is a **Rails 8** tournament management system ("Grindin Station") for organizing competitive gaming tournaments (Magic: The Gathering) with Swiss and single-elimination formats. The app also supports **Leagues** (pickup play with wagers) and **Circuits** (multi-event point standings).

### Domain Hierarchy

```
Event (abstract base)
├── Tournament (Swiss + single-elimination)
└── League (pickup play with wagers)
```

### Core Domain Models

- **Event**: Base class for Tournament/League; handles rounds, event_participants, infractions, rooms
- **Tournament**: Extends Event with Swiss + single-elimination tournament logic
- **League**: Extends Event with play/finals states, scheduled or pickup play modes, wagers
- **Circuit**: Container for multiple events with player standings
- **EventParticipant**: Player's registration and tracking within an event (Tournament or League)
- **Player**: A user's gaming identity (linked to User, has a unique key)
- **Round**: Supports SwissRound and SingleEliminationRound with complex pairing algorithms
- **Pod**: Tournament matches/tables of 4 players (3 for the remainder, per `uneven_field`)
- **Seating**: Links event_participants to pods with ordering
- **Result**: Match outcomes (Win, Draw, Loss, Eliminated, Advance, Penalty)
- **Infraction**: Tournament violations and penalties (MTG-style)
- **CircuitStanding**: Per-player standings within a circuit
- **EventOrganizer**: Organizer account linked to a User
- **Room**: Physical room assignment for events

### Key Business Logic

- **Swiss System**: Uses spread matching and forced pairing strategies in `app/services/tournaments/strategies/`
- **Tournament Structure**: `Tournaments::Structure.suggested` proposes swiss rounds and top cut (Top 4/10/13/16/40) by player count; the organiser can change both before the swiss
- **Scoring**: per-event points (`points_win`/`points_draw`/`points_loss`/`points_bye`, default 7/1/0/7), locked once the swiss starts
- **Fair seats**: `Tournaments::SeatAssigner` gives seat 1 to whoever had it least, then the cheapest order; ties drawn from the event seed; audited in `seatings.assigned_by`/`cost`. Within equal points, `PlayerSorter.deal` spreads players across pods by the seat they need
- **Rematch repair**: `Tournaments::RematchRepair` swaps players between pods while rematches decrease, nearest pods and closest points first; `CreatePodsJob` widens the allowed points gap (0, a draw, a win, two wins, …, any) only while rematches remain
- **Pairing modes** (M8, multiplayer only): `events.pairing_mode` `swiss` (default: round 2 spread, then top-down by points) | `power` (strict top-down every round, never spread) | `random` (seeded shuffle of the whole field, dealt by seat need as one group; rematch gap = any). Chosen in Settings, locked with the structure; `RematchRepair` and `SeatAssigner` run in every mode; `grindin:simulate` gates every mode; `Feeds::Info` exposes `pairingMode` (nil for 1v1). Spec `docs/superpowers/specs/2026-11-05-m8-pairing-modes.md`, numbers in `docs/superpowers/notes/2026-11-05-m8-pairing-modes.md`
- **Uneven field** (M11, multiplayer only): `events.uneven_field` `pods_of_three` (default) | `byes`, chosen in Settings, locked with the structure, 1v1 ignores it. Shape by r = n mod 4: r=1 → three 3s or 1 bye; r=2 → two 3s or 2 byes; r=3 → one 3 in both modes; n=5 → one 4 + 1 bye; pods of 5 removed. A bye is an `Advance` in the SwissRound worth `points_bye`, given from the bottom of the ranking to the lowest short count (pods of 3 + byes). `Tournaments::ShortPodRepair` runs after `RematchRepair` with the gap ladder `[0, draw, win]` so pods of 3 do not repeat; `grindin:simulate` gate "short pods (13 × 4): spread ≤ baseline and ≤ 1.563". `Feeds::Info` exposes `unevenField` (nil for 1v1). Spec `docs/superpowers/specs/2026-11-05-m11-uneven-field.md`, numbers in `docs/superpowers/notes/2026-11-05-m11-uneven-field.md`
- **Pod Sizing**: Pods of 4; the remainder plays pods of 3 or gets byes (`uneven_field`); never a pod of 5
- **Byes**: a bye scores `points_bye` but is not an opponent; byes do not count in opponents' win rate (OWR)
- **Spread Matching**: Serpentine pod assignment for spread-based rounds
- **Forced Pairing**: Rank-diff-based pairing with swap logic for forced rounds

### Event Formats

- `events.format`: `multiplayer` (default; pods of 4, plus pods of 3 or byes, seat fairness, cEDH tiebreakers) or `one_v_one` (tables of two). Chosen at creation, locked afterwards (`Event#format_locked_after_creation`); leagues are multiplayer only. `events.match_games` (3 = best-of-3, 1 = best-of-1) is editable until the swiss starts, like points. 1v1 points default to 3/1/0, bye 3.
- **Format select (2026-11-06)**: the tournament form has one Format select (`game_format`: Commander / cEDH = pods, any 1v1 game format = 1v1); `Organizer::TournamentsController#create` derives `format` from it. `GAME_FORMATS = commander standard pioneer modern legacy vintage pauper` ("other" dropped, rows moved to standard). `play.formats.multiplayer` reads "Commander / cEDH" (filters, eyebrows); `play.header.multiplayer` keeps "cEDH · pods of four". My tournaments cards show the cover behind the card and one Edit button into the roster; `/organizer/tournaments/:id/rounds` redirects to the latest round; the last swiss round offers "Finish without cut" (swiss → finished).
- **1v1 pairing**: `Tournaments::OneVOnePairer` (dispatched from `CreatePodsJob`): round 1 seeded shuffle; later rounds grouped by match points, seeded random inside the group, odd group pairs its last player down, last swiss round pairs top-down; `RematchRepair` with the same escalating gap; odd field → bye (`Advance`, no seating, 2-0) to the lowest-ranked player without one. Seats are a seeded coin flip (`assigned_by: "random"`); no seat fairness.
- **1v1 cut**: `Tournaments::OneVOneBracket` (from `CreateSingleEliminationPodsJob`): sizes 2/4/8/16/32, first round 1vN, 2vN-1 …, later rounds winners of pods `i` and `k+1-i`; vacant slots (short field, dropped winner) are walkovers. Names Finals / Semifinals / Quarterfinals / Round of 16 / Round of 32 (`rounds.cut_names`, en/pt). `Tournaments::Structure.suggested(n, format:)` follows MTR Appendix E for 1v1 (4 players → top 4, 5–8 → top 8, both straight single elimination with `swiss_rounds_count: 0`; with no swiss the cut may be the next power of two at or above the field, vacant slots being walkovers, and the swiss state is refused).
- **1v1 scoring**: results carry `games_won/lost/drawn`; `Results::Apply` takes `games:` (`{ winner: [w,l,d] }` or `{ games: [w,l,d] }` for a draw) and validates against `match_games` (bo3: 2-0, 2-1, 1-0-1 / 1-0-0 for a match stopped on time, draws 1-1-1 / 1-1-0 / 0-0-1; bo1: 1-0, 0-0-1); `Results::Timeout` writes `UNSCORED` (0-0-0, Advance only). Tiebreakers (MTR Appendix C): match points, opponents' match-win % (floor 0.33, byes excluded), game-win %, opponents' game-win %, then the seeded salt (`EventParticipant#rank_score`, integer). `standing_columns` → `{points, omw, gw, ogw}`.
- **1v1 pages/feeds**: no seat squares anywhere; scores next to the winner; standings columns Pts / OMW% / GW% / OGW% / Win % / W-L-D; feeds add `format`, `matchGames`, `games` per table and `omw/gw/ogw` per row (no `seats`). Multiplayer keys unchanged.
- Research and spec: `docs/superpowers/notes/2026-11-04-1v1-formats-research.md`, `docs/superpowers/specs/2026-11-04-1v1-format-design.md`.

### Tournament State Machine

```
draft → registration_open → registration_closed → swiss → single_elimination → finished
```

States can transition to `canceled` from most states. Defined in `Tournament::TRANSITIONS`.

Closing the last round finishes the tournament on its own (`SingleEliminationRound#advance_tournament!` after the final; `SwissRound#advance_tournament!` after the last swiss round when there is no cut; with a cut the organizer clicks "Make cut"), which runs `FinishTournamentJob` (final positions, circuit points, rankings rebuild). The public standings then follow the final positions and show a trophy on the winner. **Reopen** (`PATCH /organizer/tournaments/:id/reopen`, organizer role, header button on a finished tournament): back to `single_elimination`/`swiss` via `update_columns`, final positions cleared, the last round reopened (and its snapshot discarded if swiss), audited `event_state_changed`; closing the round again finishes. A result corrected on a closed round of a finished tournament re-runs `FinishTournamentJob` (positions, win bonus) before the rebuild.

### League State Machine

```
draft → registration_open → registration_closed → play → finals → finished
```

States can transition to `canceled` from most states. Play mode can be `scheduled` or `pickup`.

### Circuit System

- Circuits contain multiple events (Tournaments/Leagues)
- After each event, `Circuits::CalculatePoints` awards circuit points: `(total_participants - final_position + 1)`
- `CircuitStanding` tracks per-player accumulated points and events count
- Circuits have `ranked` scope (ordered by points descending)

### Rankings (M13)

- **Tables**: `ranking_contributions` (one row per player and finished event: season, `format` = the play pool (`Event#play`, M15), organizer, country/team from the player's account, field, wins/draws/byes/losses, cut/top-4/win flags, `points`, `invitational_points`) and `elo_ratings` (per player, season and `play`, `season` nil = all time: rating, peak, games, wins, previous_rating; unique `[player_id, season, play]`). Spec `docs/superpowers/specs/2026-11-05-m13-rankings-and-event-filters.md`
- **Services** (`app/services/rankings/`): `Points` (formula), `Contributions` (an event's rows), `Duels` (a pod's Elo duels), `Elo` (calculator), `Rebuild` (deletes and reinserts every contribution, replays Elo once per (season, play) and per (all time, play) over that pool's events; one transaction, advisory lock), `RebuildJob` (`app/jobs/rankings/`); `Rankings::Board` (`app/queries/rankings/`) reads the `/rankings` tables
- **Points**: per game in the Swiss rounds (and league pods) only: win 3, draw 1, loss 0, bye 1 (a penalty is a loss, a 1v1 match is one game); bonuses cut +5, top 4 +5, win +10 (tournaments only); × field factor (≤16 ×1, ≤32 ×1.25, ≤64 ×1.5, more ×2; waitlist excluded). Losses never subtract
- **Elo**: start 1500, K 32, provisional under 10 games; a pod is its pairs as duels (winner 1 against each, the others 0.5 among themselves, all-draw = draws), updated simultaneously from the ratings before the pod; cut rounds never rated; games and wins count pods. **Per play pool (M15 D6)**: `multiplayer` (cEDH pods) and each 1v1 game format are rated separately; the Leaderboard always shows one pool (`play` defaults to `multiplayer` there, chip always shown, ✕ back to multiplayer, no "All formats"; strip counts the listed rows); team average ratings read the `play` filter's pool, multiplayer under All formats. Other filters choose who is listed, never change a rating
- **Teams**: `users.team`; team points = the five best contributions (ranking points + 15 × top cuts + 30 × wins, `Board::CUT_BONUS`/`WIN_BONUS`)
- **Seasons** = calendar year of the event start; only finished events count
- **Rebuild**: `bin/rails rankings:rebuild`; nightly 05:00 (`config/recurring.yml`); `RebuildJob.schedule!` (event finished, result applied, tier changed) debounced: one run 5 min later, cache key `rankings:rebuild:scheduled`, immediate on adapters without delays
- **`/rankings`** params: `tab=points|elo|teams`, `season` (year or `all`, default the current one), `country`, `organizer` (handle), `play` (one of `Event::PLAYS`: `multiplayer standard pioneer modern legacy vintage pauper`, labels `play_label`; Points/Teams default All formats, Leaderboard `multiplayer`), `team`, `q`, `sort` (points tab: `events|wins|top_cuts|conversion`), `all=1` (beyond 20 rows). `shared/_filter_bar` (search, segment links, selects submitting on change via `submit-on-change`) + `shared/_filter_chips` (✕ per filter, Clear all); each tab's "How is … calculated?" opens a `<dialog>` (`dialog` controller; ✕, Escape, backdrop)
- **Tiers** (admin-only, never public): `events.tier` `none|bronze|silver|gold|platinum` (× 0/1/1.5/2/3 → `invitational_points`), set on `/admin/events`; `/admin/invitational` (season leaderboard + audited CSV)
- **Events**: `events.country` (ISO 2, Settings, defaults to the organizer's); one entry per player and event (unique partial index + `Registrations::AlreadyEnrolled`); guests get `players.guest_name`, distinct within the event, blank = "Manual player N"

### Feed (2026-11-06)

- `posts` (author `user`, `event`, `kind` report|note|result, `body` ≤ 1000, `likes_count`, `reports_count`, `hidden`), `post_likes` and `post_reports` (one per person each). `/feed` (`PostsController`, public layout; `?circuit=<id>` narrows to one circuit's events) lists visible posts newest first, 20 per page, with a folded composer ("Post about an event": finished events the viewer played or organizes, `Post.postable_events_for`). The event's organizer posts `note`s; `Tournaments::FinishTournamentJob#post_result` writes one `result` post per finish (`feed.result_body`). Likes toggle (`POST /feed/posts/:id/like`); reports (`POST …/report`, never on own posts) hide a post at `Post::REPORTS_TO_HIDE` (3) until an admin keeps or removes it on `/admin/feed` (audited `post_kept` / `post_removed`). Removal: author, the event's organizer, admins. `Post::BLOCKED_WORDS` refuses plain insults (pt/en/es); 5 posts per 10 min per IP. Community rules under `feed.policy` shown on the page. Circuit pages show their last 3 visible posts with "See all". Filters live in `Posts::Feed` (`app/queries/posts/`): scope everyone|following (account default `users.feed_scope`, `follows` table, Follow buttons on `/p/:handle` and `/o/:handle`), `play`, `organizer` (handle), `event` (links only), `mine` (events the viewer played/organizes), `mentions` (@handle), `sort` new|top (likes, last 7 days). **Pause**: `/admin/feed` "Pause feed" (`SiteSetting` key `feed_paused`, audited `feed_paused`) shows a notice instead of the list and refuses posts/likes/reports. The visitors' default page (no filters, page 1) is a 30 s fragment cache. Load test 2026-11-06 (dev server, Mac): 10 events' pairings at 100 concurrent clients ≈ 60 req/s total, p50 1.6 s, 0 failures; /feed 50 concurrent ≈ 74 req/s uncached.

### Infraction System (MTG-style)

Infractions have a hierarchical enum structure:
- **kind**: `game_play_errors` (200), `tournament_errors` (300), `unsporting_conduct` (400)
- **category**: Subcategories must match their parent kind (e.g., `missed_trigger` 201 requires `game_play_errors` 200)
- **penalty**: `warning` (0), `game_loss` (1), `match_loss` (2), `disqualification` (3), `priority_skip` (4)
- Auto-creates associated `Penalty` results for match_loss/disqualification infractions
- Each infraction can reference an `event` or a `pod` (or both)

### Scoring & Wagers

- **Match Points**: wins, draws, losses and byes times the event's points
- **Rank Score**: top cut advancements, then match points, then the fixed tiebreakers in order: opponents' win rate (each opponent floored at a draw), opponents beaten, unique opponents, and last a seeded salt (`tiebreak_salt`, from the event seed)
- **League Scores (wagers)**: `Scoring::PointWager` starts all participants at 1000 points, calculates forward and reverse through rounds, and averages the two for the final `league_score`
- Wager percentage per event determines what portion of each player's score is at risk

### Authentication & Authorization

- Rails 8 built-in authentication (removed Devise)
- Session-based authentication via `Session` model
- Sign in with Google/Discord via OmniAuth (`config/initializers/omniauth.rb`, `Identity` model/`identities` table, `Accounts::ConnectIdentity`); needs `GOOGLE_CLIENT_ID/SECRET`, `DISCORD_CLIENT_ID/SECRET` (buttons hidden when unset); never auto-links by e-mail (an existing account signs in with its password and links from `/account`); an unverified provider e-mail never creates a user
- `/account` (profile, handle, visibility `public|participants|private`, team (30 chars, shown as a tag next to the name), avatar via Active Storage, needs libvips; delete = `Accounts::Anonymize`, "Removed player")
- **Public profile (M12)** `/p/:handle`: header (avatar, name + team tag, handle, country, bio), band from `Profiles::Summary` (events, top cuts, win rate = wins ÷ games, conversion = cuts ÷ events, "–" without a denominator; achievements wins / top 4 / top cuts; four most played commanders with count, share and bar), then search + year + season filters and a sortable table (date desc default, event, result) of finished events with a "+" detail row (record, win rate, seats taken, seat 1 share, seat per round). `profile_events_controller` (Stimulus) filters, sorts, shows 6 rows until "Show all" and recomputes the band from the matching rows with the same figures; without JavaScript the server-rendered table and totals stay
- **E-mail confirmation (2026-11-07)**: the public sign-up creates an unconfirmed account (`users.confirmed_at` nil via `User#needs_confirmation`; the column default confirms every other creation: OAuth, organizer-added, fixtures, existing rows), sends `ConfirmationsMailer#confirm` (`generates_token_for :email_confirmation`, 2 days, voided by an e-mail change) and starts no session; `GET /confirmations/:token` confirms and signs in; `SessionsController#create` refuses an unconfirmed account (`flash.alert.confirm_first`); `/confirmations/new` resends (5 per e-mail / 20 per IP per 10 min); a password reset also confirms (the mail proved the mailbox). Audit `email_confirmed`, `confirmation_resent`. Preview at `/rails/mailers/confirmations_mailer/confirm`
- **E-mail change confirmation (2026-11-07)**: changing the e-mail on `/account` (current password required) stores it in `users.unconfirmed_email` and mails `ConfirmationsMailer#change` to the new address (`generates_token_for :email_change`, 2 days); the link (`GET /confirmations/:token`) applies it (`User#apply_email_change!`, refused if taken meanwhile), audits `email_changed`, resets the sessions. Until then the old address signs in; the account page shows the pending address
- **Player key**: `players.key` is an opaque random id (`Player.new_key`, `p-…`; guests `guest-…`, removed accounts `removed-…`), never derived from the e-mail or name (the old MD5 keys were rotated by migration 20261107200000)
- Password reset functionality with `PasswordsMailer`
- `EventOrganizer` namespace for tournament management functions
- **Site admin (M9)**: `users.admin` (never in strong params; only `bin/rails "grindin:admin[email]"` / `grindin:admin:revoke[email]`); `Admin::BaseController` answers 404 to non-admins; `/admin` (Overview: people/events counts, 12-week and 12-month sparklines, tournament-day health per ongoing event, errors summary, recent audit), `/admin/audit` (filters action/user/event/dates, 50 per page), `/admin/errors` (unresolved groups by fingerprint + Resolve, CSP reports 30 d, rate limits 7 d; `/admin/errors/:fingerprint`), `/admin/events` (filters q/state/play/tier/organizer, play = `Event::PLAYS` via `Event.with_play`, Featured toggle, tier), `/admin/invitational` (M13, + `export.csv`), `/admin/organizers` (M13: waiting-list signups Pending/Approved/Declined with search; Approve needs an account with that e-mail, creates the `EventOrganizer`, audits and e-mails; Decline; Revoke only without events or circuits). Read-only otherwise; the topbar shows an "Admin" chip to admins
- **Audit log**: `audit_events` written by `Audit.record(action, actor:, subject:, event:, **data)` (actions in `AuditEvent::ACTIONS`; never raises; savepoint so a failed insert cannot poison the caller's transaction) from the controllers/services that know the actor (sign-ins and failures, sign-ups, OAuth, password/e-mail changes, account deletion, identities, staff, result corrections on closed rounds, round close/undo, drops, event state changes, infractions, featured, tier changes, organizer approvals/declines/revokes, admin grants, data exports); `rate_limited` from the `rate_limit.action_controller` subscriber, one row per ip+action per minute. `Current` carries `ip_address`, `request_id`, `request_path`
- **Errors**: `ErrorRecorder` subscribed to `Rails.error` (not in test) writes `error_events` (fingerprint = class + first app frame; `source` request/job/other; resolve sets `resolved_at`); `POST /csp-reports` stores `csp_reports` (64 KB cap, fields cut at 2048). `Admin::TrimJob` nightly 04:30 keeps audit 12 months, errors 90 days, CSP 30 days
- `Current` concern for request-scoped state
- Content security policy (`config/initializers/content_security_policy.rb`) is **enforced** in test and production (report-only in development, where web-console injects inline scripts): per-response nonce on the importmap/module scripts, a hash for the font-swap `onload` in `_phone_head`, inline styles allowed (Tailwind/Turbo). `Permissions-Policy` header set in `config/initializers/permissions_policy.rb`. `test/system/content_security_policy_test.rb` fails on any console violation on the landing, play and organizer round pages
- Security round 2026-11-07 (Claude Security scan, 19 findings fixed): the organizer role is never self-granted at sign-up (admin approval only); `swiss_rounds_count` ≤ `Tournament::MAX_SWISS_ROUNDS` (20); the Organizer mode toggle is built from path parameters only; the deploy requires `SSH_KNOWN_HOSTS` (no `ssh-keyscan`); the Add player lookup matches a full e-mail only and hides private profiles in name mode; a password reset also unlinks OAuth identities; self-registration needs a player, is refused outside `registration_open` and is rate-limited; the rounds feed has no seeds while standings are hidden; Follow and team invitations cannot resolve hidden profiles; staff tooltips show the player id, anonymising rotates `players.key`; the recorded request path hides the reset token; SMTP STARTTLS is mandatory; the teams migration no longer backfills ownership from the free-text tag

### Frontend Stack

- **Hotwire**: Turbo + Stimulus for reactive UI
- **Tailwind CSS 4**: With Flowbite components (@tailwindcss/forms, @tailwindcss/typography, @tailwindcss/container-queries)
- **Importmap**: JavaScript module management
- **Herb**: ERB template engine with JSX-like syntax support (includes `reactionview` gem for validation)
- **Icons**: local SVG sprite (`app/assets/images/icons.svg`, `icon` helper); no icon CDN
- **Flowbite**: organizer entry point only (importmap `preload: "organizer"`); public pages ship none
- **Turbo Streams**: live updates (see Background Jobs)
- **Design (M7, one design everywhere)**: palette A dark only (tokens in `app/assets/tailwind/application.css`), Sora + Manrope. Pieces: `shared/_mark` (the S-gear mark; rotates only in the top bar and the event-header corner, honours reduced motion; `mark.svg` favicon), `shared/_topbar` (every layout: nav Events · Rankings · About, EN/PT/ES switch, account / Organizer mode), `shared/_event_header` (`evhead`, locals `event:`, `eyebrow:`, `title:`, `line:`, `actions:`), `shared/_tabs` (organizer tournament tabs), `card` + `card-title` (dark title band), `ctable` and the darker `th`, `seg`, `tab`, `.field`, `button_classes(kind = :secondary, extra = nil, size: :md)`, `desk_chip`, `event_state_chip`, event tickets (`shared/_event_ticket`, rendered directly by `pages/home` for Upcoming, via `shared/_ticket_grid` on `/events`, `/tournaments`, `/leagues`, circuits; the landing's Featured use `shared/_featured_ticket`), the `.lp-tex` texture (grain + hairline grid + soft accent light) on the landing cards. Trophy = grey line icon; no emoji, no Flowbite purple/orange, no `gray-`/`dark:` classes (`grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0)
- **Layouts**: `application` (organizer, lists, account), `play` (public event pages `/t/:slug/...`), `public` (landing, profiles), `auth` (sign in/up, forgot/reset: one centred card); also `modal` / `modal_page` (Turbo-frame modals and their full-page fallback), `print` (A4 pairings and slips), `timer` (full-screen round clock)
- **Languages**: `config/locales/{en,pt,es}.yml`; `POST /locale` stores the `locale` cookie and returns to the page (`?locale=` still overrides and updates it); `test/i18n_parity_test.rb` keeps the three files key for key

### Tournament Day

- **Play namespace** (`Play::`, `/t/:slug/...`): player-facing `me` (table), report/confirm/contest per pod, judge calls, round timer
- **Staff roles**: `event_staff` (`organizer`/`judge`/`scorekeeper`); gate actions with `allow_roles` in `Organizer::OrganizerController`
- **Helpers**: `PaletteHelper` (palette A buttons, chips, seat squares; dark only), `RosterHelper` (roster desk counters and rows)
- **Stimulus**: `pod_result` (tap a row to pick the winner, then confirm), `row_expander` (expandable roster stats)
- **Printing**: `GET /organizer/{tournaments,leagues}/:id/rounds/:id/print` (12 pods per A4) and `/slips` (6 QR slips per A4)
- **Export (M10)**: `GET /organizer/{tournaments,leagues}/:id/export/{players,melee,standings,rounds}.csv` and, for tournaments, `export/pairings?round=N` and `export/sheet` (print layout: player list, one block per closed round, final standings). Organizer + scorekeeper only; every download audited `data_exported`. CSV POROs in `app/services/exports/` (`Exports::Players` = EventLink invite list, one e-mail or name per line, no header; `Melee` = `Email,FirstName,LastName,WizardsAccountDisplayName`; `Standings`; `Rounds` long format; `Pairings` = TopDeck `Table,Player1..5`), UTF-8 BOM + CRLF via `Exports::CsvFile`. `players.wizards_email` (set at `/account`, staff-only) → `Player#reporting_email` falls back to the sign-in e-mail. EventLink has no results import; Commander events are filed as "Player List Only" (research: `docs/superpowers/notes/2026-11-05-m10-export-research.md`). Overview tab shows the Export card

### Public API (stream kit feeds)

- **Namespace** `Api::V1` (`app/controllers/api/v1/`): `BaseController` has no auth/CSRF, `expires_in 30.seconds, public: true`, ETag/Last-Modified from `Feeds.last_change` (includes participants' users, so renames invalidate), `rate_limit` 120/min per IP → 429 `{"error":"rate_limited"}`; draft/canceled events and unknown slugs return 404 `{"error":"not_found"}`
- **Serializers** `Feeds::Standings`, `Feeds::Rounds`, `Feeds::Info` (`app/serializers/feeds/`, POROs with `call(event, updated:)`) plus `Feeds` helpers; keys mirror the TopDeck relay the OBS kit reads: `updated` epoch seconds (all three), per round `start`/`end` epoch seconds (nil until started/closed) and `clock` seconds, per table `ended` epoch seconds (completed only); standings `id` = `player_id` (UUID, never `player.key`); no decklists, cut rounds named "Top N", `seats` is an object (the kit ignores it), `latest`/`roundTime`/`timerEnd` kept; standings `movement` = places moved up between the two latest closed rounds (null before round 2)
- **Stream kits**: the generic "cEDH PT" kit (`~/Desktop/cEDH PT/Content/Stream Kit/cEDH PT/src`, Podcast tab) accepts a Grindin event link (`https://<host>/t/<slug>`) and reads `standings`/`rounds`/`info` straight from this API (`pod.js`, `control.html`; done 2026-11-04). The P9Q kit (`P9Q 2026/src/kit.js`) is untouched by decision of the owner; if it is ever adapted: `const API` + fetch path (`<base>/api/v1/events/<slug>/<feed>`), `standingsTid` must accept `/t/<slug>`, the `commanders` feed (`crew.php`) has no equivalent (use the feed's `commander` or set autoCmd off), and the "Live from TopDeck" label
- CORS `*` for `/api/v1/*` only (`config/initializers/cors.rb`, rack-cors)

### Background Jobs

Uses Solid Queue for job processing:
- **Tournaments**: `StartSwissRoundJob`, `StartSingleEliminationRoundJob`, `FinishTournamentJob`, `CreatePodsJob`, `CreateSingleEliminationPodsJob`, `FinishRoundJob`
- **Leagues**: `StartPlayRoundJob`, `StartFinalsRoundJob`, `FinishLeagueJob`, `CreatePickupPodJob`
- **Events**: `GeocodeJob`, `SubmitResultJob`
- **Results**: `Results::ExpirePendingJob` (recurring, every minute): pending results unconfirmed after `confirmation_timeout_minutes` go to staff review, never auto-accepted
- **Circuits**: `UpdateStandingsJob`
- **Rankings**: `Rankings::RebuildJob` (nightly 05:00; debounced 5 min after an event finishes, a result is corrected on a closed round or a tier changes)
- **Live** (Turbo Streams): `Live::BroadcastTableJob` (a participant's table), `Live::BroadcastPodJob`, `Live::BroadcastRoundJob` (organizer round page via state partial + morph refresh). `refresh_pairings` morph-refreshes the public pairings page (all rounds, any pod change); `refresh_standings` morph-refreshes the public standings page (round published/closed, or a pod change on a closed round)
- Tournaments record `final_position` at finish (used by circuit points)
- **Standings snapshots**: `Round#round_finished` writes `Standings::Snapshot` (each participant's rank, `Feeds::Standings.ranked` order, keyed by round number) before advancing; swiss rounds only (no cut rounds, no leagues); a result corrected on a closed swiss round re-writes the snapshot of the latest closed swiss round only (earlier rounds stay historical); undoing a round discards the reopened round's snapshot and later ones. `EventParticipant#movement_since_last_round` (one query per standings load) feeds the ▲n/▼n/– arrows (`shared/_movement`) and the feed
- **Registration & check-in** (M16, Settings group "Registration & check-in"): `events.decklist_required` (default off: the decklist is optional at registration and in the "You" card of `/t/:slug`, editable until the swiss starts (`Event#points_locked?`), then locked for players; staff still edit it from the roster), `self_check_in_enabled` (default on) + `check_in_opens_hours_before` (default 3) → `Event#check_in_opens_at` / `#check_in_open?`; `PATCH /tournaments/:id/event_participants/check_in` (signed-in enrolled player, not waitlisted, window open, before the swiss) stamps `checked_in_at`; the "You" card shows the Check in button in the window and "Check-in opens at …" before it. The roster check-in is unchanged
- **Live preview** (New tournament + Settings, `xl` and up): `app/views/organizer/tournaments/{new,edit}.html.erb` wrap the form card and an `<iframe>` in `live_preview_controller.js`, which rebuilds the iframe URL from the form's fields 400 ms after each change. `Organizer::PreviewsController` (`GET /organizer/tournaments/preview`, `GET /organizer/tournaments/:id/preview`) assigns the values to an unsaved record (placeholder slug/id) and renders `play/events/show` in the play layout; the cover (a file) and the state are not previewed; CSP `frame-ancestors 'self'`. The permitted settings live in `Tournament::SETTINGS_ATTRIBUTES` (shared with `Organizer::TournamentsController`), `Tournament.format_for_game` maps the Format select to `format`
- **Standings display options** (M14, tournaments only, Settings group "Standings"): `events.show_beaten_in_standings` / `show_unique_in_standings` (default off) add the Beaten / Unique columns, tooltips and help lines to the public standings (`/t/:slug/standings` and the modal); `hide_standings_until_finished` (default off) → `Event#standings_hidden?` (set and not finished): the public page and modal show the card "Standings are published when the tournament ends" instead of the table (Standings tab kept) and `Feeds::Standings` returns `standings: []`. Organizer mode (roster, desk rows) always shows everything; the tiebreaker order is unchanged

### Deployment

- **Kamal 2** (`config/deploy.yml`, `.kamal/secrets`) to a single VPS: image `ghcr.io/kakahpt/grindin-station`, kamal-proxy with Let's Encrypt, Postgres/PostGIS accessory on `127.0.0.1` (`config/postgres/init.sql` creates the `grindin_app` role, not a superuser, and the 4 databases it owns, plus the extensions; the app connects as `grindin_app`, the `grindin` superuser is for the accessory and backups), Active Storage on `/rails/storage` (`production_local`), Solid Queue inside Puma. Host/domain from `GS_VPS_HOST`/`GS_DOMAIN`; health check `/up`
- **Workflows**: `.github/workflows/ci.yml` (tests, lint, simulation, and a `docker` job that builds the image); `.github/workflows/deploy.yml` deploys after green CI on `main`, or manually via Run workflow (`setup` for the first deploy, `deploy` otherwise)
- Secrets: `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD` (superuser) and `POSTGRES_APP_PASSWORD` (app role), hex only, `SSH_PRIVATE_KEY`, optional `SSH_KNOWN_HOSTS`, OAuth and SMTP; see `docs/superpowers/notes/2026-11-04-m4-vps-checklist.md`
- Not yet verified without a VPS/Docker: image build, Let's Encrypt, `init.sql`, workflow, cron, restore

### Database

- **PostgreSQL** with PostGIS for location data (activerecord-postgis-adapter)
- **UUID primary keys** across all models (pgcrypto `gen_random_uuid()`)
- **Solid Cache**, **Solid Queue**, and **Solid Cable** for Rails infrastructure
- **Kaminari** for pagination
- **pgcrypto** extension enabled (for `gen_random_uuid()`)

### Testing

- Minitest with system tests using Capybara/Selenium (headless Chrome); `use_phone_viewport` emulates a 390 px phone over CDP (headless Chrome will not shrink a window below 500 px)
- SimpleCov for coverage reporting with parallel worker support
- WebMock for HTTP stubbing in tests
- Fixtures in `test/fixtures/` with sample tournament data
- Service tests in `test/services/`
- Tournament-day flows (self-report/confirm/contest, judge calls, round close/cut/undo, roster, printing) have controller tests plus system tests
- Performance: `bin/rails "grindin:lighthouse[url]"` (mobile Lighthouse, fails below 90); scores in `docs/superpowers/notes/2026-11-04-m3-lighthouse.md` and `2026-11-04-m7-lighthouse.md`
- Run with parallel workers: `bin/rails test` (uses `:number_of_processors` workers)

## Code Conventions

- Ruby style follows Rails Omakase via rubocop-rails-omakase
- Frozen string literals enforced (`# frozen_string_literal: true`)
- Strong parameters validation using `params.expect` (Rails 8 permit API)
- Service objects in `app/services/` with module namespaces
- Concern-based organization for shared behavior
- ActiveJob for background processing
- STI for Event types (Tournament, League) and Result types (Win, Draw, Loss, Eliminated, Advance, Penalty)
- Double-quoted strings (Style/StringLiterals)
- Explicit block forwarding (Naming/BlockForwarding: explicit)
- Hash syntax shorthand disabled (Style/HashSyntax: never)
- **Merging:** the repository has no branch protection (private, free plan). Merge a PR only after `gh pr checks <n>` shows all five checks passing (lint, scan_ruby, scan_js, test, docker); `bin/brakeman --no-pager` locally before opening a PR.

## Rubocop Config Highlights

- Plugins: `rubocop-rails`, `rubocop-performance`, `rubocop-capybara`
- `Style/CollectionMethods`: prefer `map` over `collect`, `find` over `detect`, `reduce` over `inject`, `select` over `find_all`
- `Style/HashSyntax`: `EnforcedShorthandSyntax: never` (use `key: value` not `{key}`)
- `Style/NumericLiterals`: `MinDigits: 15` (underscore separators for large numbers)

## Routes Structure

```
GET  /                           → pages#home (landing: fair seats, waiting list, Featured tournaments, upcoming tournaments)
POST /waitlist                   → waitlist_signups#create (organiser waiting list, 5 per 10 min per IP)
POST /locale                     → locales#update (EN/PT/ES switch: locale cookie, back to the page)
POST /registrations              → registrations#create
GET/POST /session                → sessions (create/destroy)
POST /passwords/:token           → passwords (reset)
GET  /tournaments                → tournaments#index (tickets, ?filter=past; show redirects to /t/:slug, rounds/:id to /t/:slug/pairings?round=N)
GET  /leagues                    → leagues#index/show (tickets; league page with the event header)
GET  /circuits                   → circuits#index/show (organizer circuits: cards, standings table, event tickets; linked from /rankings)
GET  /events                     → events#index (tickets, ?filter=past; filters q/season/country/organizer/play (`Event::PLAYS` via `Event.with_play`), chips, Featured strip, ?view=grid|list remembered in cookie `events_view`)
GET  /rankings                   → rankings#show (tab=points|elo|teams + filters, see Rankings)
GET  /auth/:provider/callback    → omniauth_callbacks#create (+ /auth/failure)
GET/PATCH/DELETE /account        → accounts (DELETE /account/identities/:id unlinks)
GET  /p/:handle                  → profiles#show (public profile, history)
GET  /notifications              → notifications#index
GET  /up                         → rails/health#show (health check)
GET  /admin, /admin/audit, /admin/errors(/:fingerprint), POST /admin/errors/:fingerprint/resolve, /admin/events, PATCH /admin/events/:id/{featured,tier}, /admin/invitational(/export.csv), /admin/organizers + PATCH /admin/organizers/:id/{approve,decline,revoke} → admin/* (site admins only, 404 otherwise)
GET  /api/v1/events/:slug/{standings,rounds,info} → api/v1/events (public JSON, 30 s cache, CORS)

Play namespace (/t/:slug, public; draft/canceled events 404 for non-staff):
GET  /t/:slug                    → event page (counts; own entry, decklist, cancel)
GET  /t/:slug/pairings           → pairings (?round=N)
GET  /t/:slug/standings          → standings (Win %)
GET  /t/:slug/timer, /t/:slug/me → round timer, player's table

Organizer namespace (requires organizer auth):
GET/POST /organizer              → organizer/tournaments#index (root)
REST /organizer/tournaments      → CRUD + event_participants, infractions, rounds/pods/results/infractions/seatings
POST /organizer/leagues/:id/create_pickup_pod
REST /organizer/leagues          → CRUD + same nested resources
REST /organizer/circuits         → CRUD + nested tournaments (new/create)
```

## Key Files to Understand

- `app/models/event.rb`: Base class for Tournament/League, handles shared event logic
- `app/models/tournament.rb`: Swiss + single-elimination tournament logic
- `app/models/league.rb`: League/pickup play with wagers
- `app/models/event_participant.rb`: Player registration, scoring, rank calculations
- `app/models/infraction.rb`: MTG-style infraction system
- `app/models/result.rb`: STI for match outcomes
- `app/models/circuit.rb`: Multi-event standings container
- `config/routes.rb`: Nested resource structure with organizer namespace
- `app/services/tournaments/strategies/swiss_matcher.rb`: Swiss pairing with swaps
- `app/services/tournaments/strategies/spread_matcher.rb`: Serpentine spread matching
- `app/services/tournaments/uneven_pod_generator.rb`: pod sizes (4s, then 3s or byes)
- `app/services/scoring/point_wager.rb`: League score/wager calculations
- `app/services/circuits/calculate_points.rb`: Circuit point awards
- `app/models/play/table_state.rb`: state of a player's table (page and Turbo broadcasts)
- `app/queries/profiles/history.rb`: public profile history (position, W-L-D, seats, decklist rules)
- `app/services/accounts/`: `ConnectIdentity` (OmniAuth), `Anonymize` (account deletion)
- `app/jobs/live/`: Turbo Stream broadcast jobs
- `app/controllers/concerns/authentication.rb`: Auth implementation
- `app/controllers/application_controller.rb`: Base controller with Prosopite N+1 detection

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
- **Backups** (run on the VPS): `bin/backup` (pg_dump of the primary DB, keeps 14, optional rclone), `bin/restore <file>`
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
- **Pod**: Tournament matches/tables with 3-5 players per pod
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
- **Pod Sizing**: Prefers 4-player pods, allows 3-5 players with sophisticated balancing
- **Byes**: a bye scores `points_bye` but is not an opponent; byes do not count in opponents' win rate (OWR)
- **Spread Matching**: Serpentine pod assignment for spread-based rounds
- **Forced Pairing**: Rank-diff-based pairing with swap logic for forced rounds

### Tournament State Machine

```
draft → registration_open → registration_closed → swiss → single_elimination → finished
```

States can transition to `canceled` from most states. Defined in `Tournament::TRANSITIONS`.

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
- `/account` (profile, handle, visibility `public|participants|private`, avatar via Active Storage, needs libvips; delete = `Accounts::Anonymize`, "Removed player")
- Password reset functionality with `PasswordsMailer`
- `EventOrganizer` namespace for tournament management functions
- `Current` concern for request-scoped state

### Frontend Stack

- **Hotwire**: Turbo + Stimulus for reactive UI
- **Tailwind CSS 4**: With Flowbite components (@tailwindcss/forms, @tailwindcss/typography, @tailwindcss/container-queries)
- **Importmap**: JavaScript module management
- **Herb**: ERB template engine with JSX-like syntax support (includes `reactionview` gem for validation)
- **Icons**: local SVG sprite (`app/assets/images/icons.svg`, `icon` helper); no icon CDN
- **Flowbite**: organizer entry point only (importmap `preload: "organizer"`); public pages ship none
- **Leaflet**: vendored in `vendor/javascript`, loaded lazily
- **Turbo Streams**: live updates (see Background Jobs)

### Tournament Day

- **Play namespace** (`Play::`, `/t/:slug/...`): player-facing `me` (table), report/confirm/contest per pod, judge calls, round timer
- **Staff roles**: `event_staff` (`organizer`/`judge`/`scorekeeper`); gate actions with `allow_roles` in `Organizer::OrganizerController`
- **Helpers**: `PaletteHelper` (palette A buttons, chips, seat squares; dark only), `RosterHelper` (roster desk counters and rows)
- **Stimulus**: `pod_result` (tap a row to pick the winner, then confirm), `row_expander` (expandable roster stats)
- **Printing**: `GET /organizer/{tournaments,leagues}/:id/rounds/:id/print` (12 pods per A4) and `/slips` (6 QR slips per A4)

### Public API (stream kit feeds)

- **Namespace** `Api::V1` (`app/controllers/api/v1/`): `BaseController` has no auth/CSRF, `expires_in 30.seconds, public: true`, ETag/Last-Modified from `Feeds.last_change` (includes participants' users, so renames invalidate), `rate_limit` 120/min per IP → 429 `{"error":"rate_limited"}`; draft/canceled events and unknown slugs return 404 `{"error":"not_found"}`
- **Serializers** `Feeds::Standings`, `Feeds::Rounds`, `Feeds::Info` (`app/serializers/feeds/`, POROs with `call(event, updated:)`) plus `Feeds` helpers; keys mirror the TopDeck relay the OBS kit reads: `updated` epoch seconds (all three), per round `start`/`end` epoch seconds (nil until started/closed) and `clock` seconds, per table `ended` epoch seconds (completed only); standings `id` = `player_id` (UUID, never `player.key`); no decklists, cut rounds named "Top N", `seats` is an object (the kit ignores it), `latest`/`roundTime`/`timerEnd` kept
- **Kit adaptations still needed** (P9Q SetUp `src/kit.js`): `const API` + fetch path (`<base>/<slug>/<feed>` instead of `?feed=X&tid=Y`); `standingsTid` regex must accept a bare slug or `/t/<slug>`; the `commanders` feed (`crew.php`) has no equivalent (use the feed's `commander` or set autoCmd off); the "Live from TopDeck" label. Everything else matches
- CORS `*` for `/api/v1/*` only (`config/initializers/cors.rb`, rack-cors)

### Background Jobs

Uses Solid Queue for job processing:
- **Tournaments**: `StartSwissRoundJob`, `StartSingleEliminationRoundJob`, `FinishTournamentJob`, `CreatePodsJob`, `CreateSingleEliminationPodsJob`, `FinishRoundJob`
- **Leagues**: `StartPlayRoundJob`, `StartFinalsRoundJob`, `FinishLeagueJob`, `CreatePickupPodJob`
- **Events**: `GeocodeJob`, `SubmitResultJob`
- **Results**: `Results::ExpirePendingJob` (recurring, every minute): pending results unconfirmed after `confirmation_timeout_minutes` go to staff review, never auto-accepted
- **Circuits**: `UpdateStandingsJob`
- **Live** (Turbo Streams): `Live::BroadcastTableJob` (a participant's table), `Live::BroadcastPodJob`, `Live::BroadcastRoundJob` (organizer round page via state partial + morph refresh). Public pairings are not live yet
- Tournaments record `final_position` at finish (used by circuit points)

### Deployment

- **Kamal 2** (`config/deploy.yml`, `.kamal/secrets`) to a single VPS: image `ghcr.io/kakahpt/grindin-station`, kamal-proxy with Let's Encrypt, Postgres/PostGIS accessory on `127.0.0.1` (`config/postgres/init.sql` creates the 4 databases), Active Storage on `/rails/storage` (`production_local`), Solid Queue inside Puma. Host/domain from `GS_VPS_HOST`/`GS_DOMAIN`; health check `/up`
- **Workflows**: `.github/workflows/ci.yml` (tests, lint, simulation, and a `docker` job that builds the image); `.github/workflows/deploy.yml` deploys after green CI on `main`, or manually via Run workflow (`setup` for the first deploy, `deploy` otherwise)
- Secrets: `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD` (hex only), `SSH_PRIVATE_KEY`, optional `SSH_KNOWN_HOSTS`, OAuth and SMTP; see `docs/superpowers/notes/2026-11-04-m4-vps-checklist.md`
- Not yet verified without a VPS/Docker: image build, Let's Encrypt, `init.sql`, workflow, cron, restore

### Database

- **PostgreSQL** with PostGIS for location data (activerecord-postgis-adapter)
- **UUID primary keys** across all models (pgcrypto `gen_random_uuid()`)
- **Solid Cache**, **Solid Queue**, and **Solid Cable** for Rails infrastructure
- **Kaminari** for pagination
- **pgcrypto** extension enabled (for `gen_random_uuid()`)

### Testing

- Minitest with system tests using Capybara/Selenium (headless Chrome)
- SimpleCov for coverage reporting with parallel worker support
- WebMock for HTTP stubbing in tests
- Fixtures in `test/fixtures/` with sample tournament data
- Service tests in `test/services/`
- Tournament-day flows (self-report/confirm/contest, judge calls, round close/cut/undo, roster, printing) have controller tests plus system tests
- Performance: `bin/rails "grindin:lighthouse[url]"` (mobile Lighthouse, fails below 90); scores in `docs/superpowers/notes/2026-11-04-m3-lighthouse.md`
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

## Rubocop Config Highlights

- Plugins: `rubocop-rails`, `rubocop-performance`, `rubocop-capybara`
- `Style/CollectionMethods`: prefer `map` over `collect`, `find` over `detect`, `reduce` over `inject`, `select` over `find_all`
- `Style/HashSyntax`: `EnforcedShorthandSyntax: never` (use `key: value` not `{key}`)
- `Style/NumericLiterals`: `MinDigits: 15` (underscore separators for large numbers)

## Routes Structure

```
GET  /                           → events#index
POST /registrations              → registrations#create
GET/POST /session                → sessions (create/destroy)
POST /passwords/:token           → passwords (reset)
GET  /tournaments                → tournaments#index (show redirects to /t/:slug)
GET  /leagues                    → leagues#index/show
GET  /circuits                   → circuits#index/show
GET  /events                     → events#index
GET  /auth/:provider/callback    → omniauth_callbacks#create (+ /auth/failure)
GET/PATCH/DELETE /account        → accounts (DELETE /account/identities/:id unlinks)
GET  /p/:handle                  → profiles#show (public profile, history)
GET  /notifications              → notifications#index
GET  /up                         → rails/health#show (health check)
GET  /api/v1/events/:slug/{standings,rounds,info} → api/v1/events (public JSON, 30 s cache, CORS)

Play namespace (/t/:slug, public; draft/canceled events 404 for non-staff):
GET  /t/:slug                    → event page (enrolled, waitlist, enrol/cancel)
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
- `app/services/tournaments/uneven_pod_generator.rb`: 3-5 player pod generation
- `app/services/scoring/point_wager.rb`: League score/wager calculations
- `app/services/circuits/calculate_points.rb`: Circuit point awards
- `app/models/play/table_state.rb`: state of a player's table (page and Turbo broadcasts)
- `app/queries/profiles/history.rb`: public profile history (position, W-L-D, seats, decklist rules)
- `app/services/accounts/`: `ConnectIdentity` (OmniAuth), `Anonymize` (account deletion)
- `app/jobs/live/`: Turbo Stream broadcast jobs
- `app/controllers/concerns/authentication.rb`: Auth implementation
- `app/controllers/application_controller.rb`: Base controller with Prosopite N+1 detection

# M9 — Admin dashboard (2026-11-05)

Owner's ask (backlog after M6, "seguir tudo o que se passa"): a site-admin role separate from event organizer;
`/admin` with counts and trends, tournament-day health, errors (exceptions, CSP reports, rate-limit hits) and an
audit log of sensitive actions with who/when/what/ip; retention with a nightly trim. Read-only except "resolve"
on an error group. Also the admin control of **Featured** events promised in M7.

Global constraint (owner, 2026-11-04 night): the M7 design everywhere — `application` layout, topbar, `card` +
`card-title`, `ctable`, `status_chip`/`desk_chip`, `button_classes`, `.field`; charts are inline SVG sparklines
in the accent colour; no new visual language. Layouts reviewed with the owner the next morning.

## 1. Role

- `users.admin` boolean, not null, default false. Never settable from sign-up, `/account` or any form (not in
  any strong params). Promoted only by `bin/rails "grindin:admin[email]"` (and demoted by
  `grindin:admin:revoke[email]`); both write an audit event `admin_granted` / `admin_revoked` with actor nil.
- `User#admin?`. `Admin::BaseController < ApplicationController`: `before_action :require_admin` → non-admins
  get 404 (`head :not_found`, no hint that `/admin` exists). Admins need no organizer account.
- Topbar: an "Admin" `topbar-chip` next to "Organizer mode", only for admins, `on` under `/admin`.

## 2. Audit log

- Table `audit_events`: `id uuid`, `action string` (not null, indexed), `actor_user_id uuid` (nullable, FK users),
  `subject_type string` / `subject_id uuid` (nullable polymorphic), `event_id uuid` (nullable, FK events, indexed),
  `ip string`, `request_id string`, `data jsonb` (default `{}`), `created_at` (indexed). No `updated_at`.
- `Current` gains `ip_address` and `request_id`, set in `ApplicationController` before any action
  (`Current.ip_address = request.remote_ip; Current.request_id = request.request_id`).
- `Audit.record(action, actor: Current.user, subject: nil, event: nil, **data)` inserts one row (never raises:
  failures are logged, never block the action). Called from the controllers/services that already know the actor,
  not from model callbacks.
- Actions and where they are written (data keys in parentheses):
  - `sign_in` (SessionsController#create success), `sign_in_failed` (same, failure; `email` as entered,
    normalised: stripped and downcased; actor nil), `sign_out` (#destroy), `sign_up` (RegistrationsController#create), `oauth_sign_in` (OmniauthCallbacks
    success; `provider`), `oauth_failed` (failure; `provider`, `reason`).
  - `password_reset_requested` (PasswordsController#create, `email`), `password_reset` (#update success),
    `password_changed`, `email_changed` (`from`, `to`) (AccountsController#update, by `saved_change_to_*`),
    `account_deleted` (AccountsController#destroy), `identity_linked` / `identity_unlinked` (`provider`).
  - `staff_added` / `staff_removed` (Organizer::StaffController; `user_id`, `role`, event).
  - `result_corrected` (Results::Apply when `closed?`; `pod_id`, `round_number`, `result`), `round_undone`
    (Organizer::RoundsController#destroy; `round_number`), `round_closed` (close), `participant_dropped`
    (Registrations::Drop; `participant_id`, `reason`), `event_state_changed` (Organizer::Tournaments/Leagues
    #update when `state_previously_changed?`; `from`, `to`), `infraction_added` / `infraction_removed`
    (`penalty`, `participant_id`), `featured_changed` (admin toggle and organizer switch; `featured`).
  - `rate_limited` (`controller`, `action`, `path`), written by one subscriber to the
    `rate_limit.action_controller` notification (no change to the `with:` lambdas), actor = current user if any;
    one row per ip and action per minute (deduped through `Rails.cache`).
- `/admin/audit`: `ctable` newest first, 50 per page (Kaminari), filters (GET params, `.field` inputs in one
  row): `action` select, `user` (e-mail contains), `event` (name contains), `from`/`to` dates. Columns: when,
  action chip, actor (e-mail or "—"), event, subject, ip, details (compact `key: value` list from `data`).

## 3. Errors

- Table `error_events`: `fingerprint string` (not null, indexed), `error_class string`, `message text`,
  `backtrace text` (first 30 lines), `path string`, `request_id string`, `user_id uuid` (nullable), `source string`
  (`request` | `job` | `other`), `resolved_at datetime` (nullable), `created_at` (indexed). Fingerprint =
  SHA256 of `error_class` + first backtrace line inside `app/` (or the message when none).
- `ErrorRecorder` subscribed with `Rails.error.subscribe` in `config/initializers/error_reporting.rb` (all
  environments except test, where it is subscribed only inside tests that need it). `report(error, handled:,
  severity:, context:, source:)` inserts one `error_events` row (and swallows its own failures). Unhandled
  controller exceptions arrive through Rails' executor; jobs through Active Job.
- Table `csp_reports`: `document_uri`, `violated_directive`, `blocked_uri`, `user_agent`, `ip`, `created_at`
  (indexed). `CspReportsController#create` parses the JSON body (`csp-report` key) and inserts; malformed bodies
  are ignored (still `204`).
- `/admin/errors`: one row per unresolved fingerprint (count, last seen, error class, message, source) with a
  "Resolve" `button_to` (sets `resolved_at` on every row of that fingerprint; audit `error_resolved`). Below it,
  "CSP reports" (last 30 days grouped by `violated_directive` + `blocked_uri`, count, last seen) and "Rate
  limits" (last 7 days grouped by controller/action, count). `/admin/errors/:fingerprint` shows the latest
  occurrence: message, backtrace in a `<pre>`, path, request id, user, and the last 20 occurrences.

## 4. Overview (`/admin`)

Cards (all queries plain SQL/Active Record, each block cached 60 s with `Rails.cache.fetch`):
- **People**: players total, new in the last 30 days, organizers, admins; sparkline of sign-ups per week (12 weeks).
- **Events**: tournaments by state (chips with counts), by format; events per month (12 months sparkline);
  average players per finished tournament.
- **Today** (tournament-day health, one row per ongoing tournament or league): event name (link to the
  organizer page), round, open judge calls, disputed tables, tables waiting for confirmation
  (`pending_result` present), tables sent to review (`review_requested_at`), late (round started, not finished
  and past `started_at + duration + max pod extra_time`). Empty state: "Nothing running".
- **Errors**: unresolved groups (count), errors in the last 24 h, CSP reports last 7 days, rate-limit hits last
  7 days; links to `/admin/errors`.
- **Recent audit**: last 10 audit events, link to `/admin/audit`.

Sparkline helper `sparkline(values, width: 120, height: 28)` → inline `<svg>` polyline, accent stroke, no axes.

## 5. Events (`/admin/events`)

`ctable` of tournaments and leagues (newest first, 50 per page): name, organizer e-mail, state chip, format,
players, start date, Featured toggle (`button_to` PATCH `/admin/events/:id/featured`, flips `featured`, audit
`featured_changed`). Nothing else is editable.

## 6. Retention

`Admin::TrimJob` nightly at 04:30 (`config/recurring.yml`, production): deletes `audit_events` older than 12
months, `error_events` older than 90 days, `csp_reports` older than 30 days. Logs the three counts.

## 7. Copy and tests

- en/pt/es keys under `admin.*`; parity test.
- Tests: role (404 for non-admin and anonymous; admin sees `/admin`; `admin` never mass-assignable), rake task,
  `Audit.record` (row shape, never raises when the insert fails), one controller test per audited action
  asserting the row (action, actor, event, data), rate-limit subscriber (with the memory store helper),
  `ErrorRecorder` (fingerprint stable across occurrences, resolve clears), CSP endpoint stores a row, overview
  renders the health row for a running tournament with a late round, audit filters, errors resolve, events
  featured toggle, trim job, topbar chip, i18n parity.

## Out of scope

4xx/5xx request rates (no request log; error counts stand in), e-mailing admins, charts beyond sparklines,
editing users or events from `/admin` (besides Featured and Resolve), multi-admin permissions.

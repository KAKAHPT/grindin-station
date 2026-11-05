# M9 Admin Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A site-admin role and `/admin` pages showing usage counts, tournament-day health, errors and an audit log of sensitive actions, with retention.

**Architecture:** Three new tables (`audit_events`, `error_events`, `csp_reports`) written by a tiny `Audit.record` service, a `Rails.error` subscriber and the CSP endpoint; `Admin::*` controllers under the `application` layout reuse the M7 pieces; counters are plain queries cached 60 s; a nightly job trims.

**Tech Stack:** Rails 8.1, Solid Queue recurring, Kaminari, Minitest.

**Spec:** `docs/superpowers/specs/2026-11-05-m9-admin-dashboard.md`

## Global Constraints

- M7 design only: `application` layout, `card`/`card-title`, `ctable`, `status_chip`, `desk_chip`, `button_classes`, `.field`; `grep -rnE "purple|orange-700|dark:|gray-" app/views` stays 0; no new CSS beyond `.sparkline` sizing.
- `users.admin` is never in strong params anywhere.
- Audit writes never raise into the calling action.
- Copy in en/pt/es; `test/i18n_parity_test.rb` passes.
- Commit with `git commit -- <paths>`; rubocop clean; brakeman clean.

## Review Focus

1. A non-admin signed-in organizer requesting `/admin` must get 404, not a redirect with a hint (Task 1 test).
2. A failed sign-in must write `sign_in_failed` with the e-mail but no password (Task 2 test asserts `data.keys == ["email"]`).
3. `Audit.record` with a broken DB insert must not break sign-in (Task 2 test stubs `AuditEvent.insert` to raise).
4. Two occurrences of the same exception from the same line must share one fingerprint; a different line must not (Task 3 test).
5. Resolve on a group must hide it from `/admin/errors` and a new occurrence after resolve must reappear as unresolved (Task 4 test).

---

### Task 1: Admin role, rake task, base controller, topbar chip, Current request data

**Files:**
- Create: `db/migrate/<ts>_add_admin_to_users.rb`, `app/controllers/admin/base_controller.rb`, `app/controllers/admin/dashboard_controller.rb` (`show` renders a placeholder card "Admin"), `app/views/admin/dashboard/show.html.erb`, `lib/tasks/admin.rake` (`grindin:admin[email]`, `grindin:admin:revoke[email]`)
- Modify: `app/models/user.rb`, `app/models/current.rb` (`attribute :ip_address, :request_id`), `app/controllers/application_controller.rb` (`before_action :set_request_context`), `config/routes.rb` (`namespace :admin { root "dashboard#show" }` → `/admin`), `app/views/shared/_topbar.html.erb` (chip after Organizer mode), `app/helpers/application_helper.rb` (`admin_mode?`), `config/locales/{en,pt,es}.yml` (`topbar.admin`, `admin.title`)
- Test: `test/controllers/admin/dashboard_controller_test.rb`, `test/models/user_test.rb`, `test/tasks/admin_rake_test.rb` (load the task with `Rails.application.load_tasks` once), `test/controllers/layout_test.rb` (chip only for admins)

**Interfaces:**
- Produces: `User#admin?`, `Admin::BaseController` (`require_admin`), route `admin_root_path`, `Current.ip_address`, `Current.request_id`.

- [ ] Step 1: Failing tests: anonymous `/admin` → 404; organizer user → 404; admin user (fixture `users(:admin_user)`, add to `test/fixtures/users.yml` with `admin: true`) → 200 and body contains "Admin"; `User.new(admin: true)` via `registrations#create` params stays false; rake task flips `admin` and writes an `AuditEvent`? — no, the audit table arrives in Task 2, so the rake test only asserts the flag here (Task 2 adds the audit assertion).
- [ ] Step 2: Implement; topbar chip markup identical to the organizer chip (`topbar-chip`, `on` when `admin_mode?`).
- [ ] Step 3: `bin/rails test test/controllers test/models` green; commit `feat(m9): admin role, /admin skeleton, request context`.

### Task 2: Audit log

**Files:**
- Create: `db/migrate/<ts>_create_audit_events.rb`, `app/models/audit_event.rb` (`ACTIONS` constant listing every action name from spec §2; `validates :action, inclusion`), `app/services/audit.rb` (`Audit.record`), `config/initializers/rate_limit_audit.rb` (subscriber to `rate_limit.action_controller`)
- Modify: every controller/service listed in spec §2 (sessions, registrations, omniauth_callbacks, passwords, accounts, organizer/staff, results/apply, organizer/rounds, registrations/drop, organizer/tournaments, organizer/leagues, organizer/infractions, organizer tournaments featured switch), `lib/tasks/admin.rake` (audit `admin_granted/revoked`)
- Test: `test/services/audit_test.rb`, `test/models/audit_event_test.rb`, assertions added to the existing controller/service tests for each action (`assert_difference -> { AuditEvent.where(action: "...").count }`), `test/controllers/rate_limit_audit_test.rb` (uses `with_memory_rate_limit_store`)

**Interfaces:**
- Consumes: `Current.user/ip_address/request_id` (Task 1).
- Produces: `Audit.record(action, actor: Current.user, subject: nil, event: nil, **data)` → `AuditEvent` or nil; `AuditEvent` scopes `recent`, `for_action(a)`, `between(from, to)`.

- [ ] Step 1: Failing tests for `Audit.record` (row shape; `AuditEvent.insert!` raising → returns nil, logs, no raise; unknown action raises `ArgumentError` in test/dev via the inclusion validation) and for each audited action.
- [ ] Step 2: Migration + model + service; instrument each site; subscriber.
- [ ] Step 3: Full `bin/rails test` green; commit in two commits: `feat(m9): audit_events and Audit.record`, `feat(m9): audit sensitive actions`.

### Task 3: Error events, CSP reports, trim job

**Files:**
- Create: `db/migrate/<ts>_create_error_events.rb`, `db/migrate/<ts>_create_csp_reports.rb`, `app/models/error_event.rb` (`fingerprint_for(error)`, scopes `unresolved`, `grouped`), `app/models/csp_report.rb`, `app/services/error_recorder.rb` (`report(error, handled:, severity:, context:, source:)`), `config/initializers/error_reporting.rb`, `app/jobs/admin/trim_job.rb`
- Modify: `app/controllers/csp_reports_controller.rb`, `config/recurring.yml` (`admin_trim: class Admin::TrimJob, schedule: every day at 4:30am`)
- Test: `test/models/error_event_test.rb`, `test/services/error_recorder_test.rb` (subscribe inside the test, raise two errors from the same line, assert one fingerprint; `Rails.error.report` with `source: "job"`), `test/controllers/csp_reports_controller_test.rb` (valid JSON stores a row; garbage → 204 no row), `test/jobs/admin/trim_job_test.rb` (rows older than the retention are gone, newer stay)

- [ ] Step 1: Failing tests.
- [ ] Step 2: Implement; the initializer guards `unless Rails.env.test?`.
- [ ] Step 3: Green; commit `feat(m9): error events, csp reports, nightly trim`.

### Task 4: Admin pages

**Files:**
- Create: `app/controllers/admin/audit_events_controller.rb` (`index`), `app/controllers/admin/errors_controller.rb` (`index`, `show`, `resolve`), `app/controllers/admin/events_controller.rb` (`index`, `featured`), `app/queries/admin/overview.rb` (`Admin::Overview.call` → struct of the §4 numbers, cached 60 s per block), `app/queries/admin/health.rb` (rows for ongoing events), `app/helpers/admin_helper.rb` (`sparkline(values, width: 120, height: 28)`), views under `app/views/admin/{dashboard,audit_events,errors,events}/`
- Modify: `config/routes.rb`, `app/views/admin/dashboard/show.html.erb` (replace the placeholder), `config/locales/{en,pt,es}.yml`, `app/assets/tailwind/application.css` (`.sparkline` only)
- Test: `test/controllers/admin/{audit_events,errors,events,dashboard}_controller_test.rb`, `test/queries/admin/health_test.rb` (late round detection with `travel_to`), `test/helpers/admin_helper_test.rb`

**Interfaces:**
- Consumes: Tasks 1–3 models.

- [ ] Step 1: Failing controller tests (filters narrow the audit list; resolve hides the group; featured toggle flips and audits; dashboard shows the health row and "Nothing running" when idle).
- [ ] Step 2: Implement with `card`/`ctable`/chips; pages share a small `admin/_nav` built with `shared/_tabs` (Overview · Audit · Errors · Events).
- [ ] Step 3: `bin/rails test` green, rubocop, parity; commit `feat(m9): admin overview, audit, errors and events pages`.

### Task 5: Docs and whole-branch verification

**Files:**
- Modify: `CLAUDE.md` (Authentication: admin role; new tables; routes; recurring job; rake tasks), `docs/superpowers/notes/2026-11-04-backlog-after-m6.md` (M9 done)

- [ ] Step 1: Update docs; `bin/rails test && bin/rails test:system && bin/rubocop && bin/brakeman -q` green.
- [ ] Step 2: Commit `docs(m9): admin dashboard`.

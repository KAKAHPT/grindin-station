# Security review (2026-11-04)

Brakeman 8.1: 0 warnings. bundler-audit: rails-html-sanitizer 1.7.1 → 1.7.2 (PR #27). Logic review (branch m6-1v1):
no cross-event id swap in the organizer namespace, no judge/scorekeeper escalation, play namespace scoped to the
player's own pod, hidden events 404 everywhere, signed Turbo streams, CSRF everywhere, force_ssl, httponly/lax
cookies, non-root image, Postgres on 127.0.0.1, filtered logs, no e-mails in feeds.

## Fixed in branch `sec-hardening`
- H1 player identity takeover via MD5 key collision (adopting an existing Player row).
- H2 one seated player could apply a result alone: self-reports refused before the round starts; cut rounds always
  need the opponent's confirmation (spec §5.5 amended for single elimination).
- M3 state transitions enforced on save; locks checked against the previous state.
- M4 login/sign-up rate limits per e-mail (10/3 min) with a looser per-IP limit (100/3 min) so a venue NAT works.
- M5 sessions expire after 30 days; other sessions destroyed on password or e-mail change; e-mail change needs the
  current password.
- M6 CSP in report-only mode with nonces.
- L7 circuit ownership; L8 cover type/size; L9 decklist locked once round 1 is published; L10 legacy round route
  published only; L11 judge-call reason length + rate limit + one open call per pod; L12 password-reset rate limit;
  L13 500s in seatings/infractions/results; L14 app DB role is not a superuser; backup dumps 0600.

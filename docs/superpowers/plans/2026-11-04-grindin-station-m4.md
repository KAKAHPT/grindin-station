# Grindin Station — Plano de implementação M4 (produção)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pôr o Grindin Station em produção num VPS Hostinger com Kamal, TLS, backups e deploy por GitHub Actions, e ligar o kit de stream (OBS) aos feeds do Grindin Station.

**Architecture:** Feeds JSON públicos em `/api/v1/events/:slug/{standings,rounds,info}` com a forma que o kit de stream já consome do relay `cedhpt.com/api/topdeck.php` (chaves `standings`, `rounds[].tables[]`, …), cache HTTP de 30 s e CORS aberto, sem decklists. Produção: um VPS com Docker; Kamal gere a app (Puma + Solid Queue dentro do Puma), o Postgres+PostGIS como accessory com volume, o kamal-proxy com Let's Encrypt; Active Storage em disco num volume; backups diários `pg_dump` para um volume e, opcionalmente, para um bucket S3-compatível via `rclone`. GitHub Actions faz `kamal deploy` em cada push a `main` depois do CI verde, com os segredos do repositório.

**Tech Stack:** Rails 8.1, Kamal 2, Docker, PostgreSQL 17 + PostGIS (imagem `postgis/postgis:17-3.5`), kamal-proxy (Let's Encrypt), GitHub Actions, `rack-cors` (novo), `rclone` (opcional, no VPS).

**Spec:** `docs/superpowers/specs/2026-10-14-grindin-station-design.md` §3, §8 (feeds), §10 M4. Formato de referência dos feeds: `~/Desktop/cEDH PT/cEDH PT Web/web/api/topdeck.php` e o consumo em `kit.js` (`json.standings`, `r.round`, `r.tables`, `t.table`, `t.status`, `t.winner`, `t.draw`, `t.players`, `p.name`, `p.commander`, `p.seed`).

## Global Constraints

- Feeds sem autenticação, `Cache-Control: public, max-age=30`, CORS `*` só em `/api/v1/*`, JSON UTF-8 sem escapar `/`. Nunca decklists nem URLs; comandantes só com `show_commanders_in_standings` (senão `commander: ""`). Eventos em rascunho/cancelados → 404.
- Forma dos feeds (compatível com o kit): standings `{tid, name, updated, standings:[{rank, name, id, commander, wins, losses, draws, points, winRate, seats:{"1":n,"2":n,"3":n,"4":n}}]}`; rounds `{tid, updated, latest, roundTime, rounds:[{round:"1"|"Top 16"|"Top 4", tables:[{table, status:"Completed"|"Active"|"Pending", winner:<nome>|"Draw"|"", draw:bool, players:[{name, commander, seed}]}]}]}`; info `{tid, name, state, starts_at, ends_at, players, round, timerEnd}`. `tid` = slug. `id` = `player.key`.
- Produção: `RAILS_MASTER_KEY`, `PRIMARY_DATABASE_URL`/`CACHE_DATABASE_URL`/`QUEUE_DATABASE_URL`/`CABLE_DATABASE_URL` (ou `DATABASE_URL` + nomes), `GOOGLE_*`, `DISCORD_*`, `SMTP_*` só por segredos; nada de credenciais no repositório. Ruby no Dockerfile = `.ruby-version` (4.0.3); `libvips` na imagem.
- Nada é executado contra o VPS real neste plano: as tarefas produzem configuração, scripts e documentação; a execução no VPS (DNS, chaves, primeiro `kamal setup`) é uma checklist para o utilizador. Qualquer passo que precise de credenciais pára e é anotado.
- Locales en/pt para qualquer copy; rubocop-rails-omakase; Brakeman limpo; CI verde.

## Review Focus

1. Um feed pedido a meio da publicação de uma ronda não pode mostrar mesas sem jogadores nem jogadores repetidos — Task 1 testa o feed `rounds` com uma ronda não publicada (ignorada) e com byes.
2. O cache de 30 s não pode servir standings de outro evento (chave por slug) — Task 1 testa dois eventos seguidos.
3. `kamal deploy` não pode correr sem CI verde nem com segredos em falta — Task 2 faz o workflow depender do job `test` e falhar cedo com mensagem clara quando um segredo não existe.
4. Backups não podem encher o disco — Task 2 roda os dumps (manter 14) e o script é idempotente.
5. A imagem tem de arrancar sem `node_modules` nem Tailwind em runtime — Task 2 verifica `docker build` local (se o Docker existir nesta máquina; senão fica anotado) e o `bin/docker-entrypoint` corre `db:prepare`.

---

### Task 1: Feeds JSON para o stream

**Files:**
- Create: `app/controllers/api/v1/base_controller.rb`, `app/controllers/api/v1/events_controller.rb` (`standings`, `rounds`, `info`), `app/serializers/feeds/standings.rb`, `app/serializers/feeds/rounds.rb`, `app/serializers/feeds/info.rb` (POROs com `call(event) -> Hash`), `config/initializers/cors.rb`
- Modify: `Gemfile` (`rack-cors`), `config/routes.rb` (`namespace :api { namespace :v1 { get "events/:slug/standings|rounds|info" } }`), `config/initializers/filter_parameter_logging.rb` (nada), `README.md` (secção feeds, Task 3 completa)
- Test: `test/controllers/api/v1/events_controller_test.rb`, `test/serializers/feeds/*_test.rb`

**Interfaces:**
- Consumes: `EventParticipant.standings_for(event)`, `seat_counts_for`, `number_of_wins/losses/draws`, `match_points`, `win_rate`, `Round#published/finished_at/started_at`, `Tournament#swiss_round_length/top_cut_round_length` (nomes reais em `app/models/tournament.rb`), `Pod#report_status`, `Round#display_name` (M3 Task 6) para "Top 16".
- Produces: as três rotas com a forma das Global Constraints; `Api::V1::BaseController` (`skip_before_action :require_authentication`, `skip_forgery_protection`, `before_action :set_cache`, `rescue_from ActiveRecord::RecordNotFound` → `{error:"not_found"}` 404). Cache: `expires_in 30.seconds, public: true` + `fresh_when` por `updated_at` máximo (event, rounds, pods, results).

- [ ] **Step 1: Testes** (`events_controller_test.rb`: standings de um torneio com 2 rondas jogadas devolve `standings` ordenadas por rank com `seats` e `commander` vazio por defeito; com `show_commanders_in_standings` devolve o comandante mas nunca um URL; `rounds` ignora rondas não publicadas, lista byes como mesa `status: "Pending"`? → **não**: byes não aparecem nas `tables` (o kit não os espera); cada jogador aparece uma vez por ronda; `info` devolve `round` actual e `timerEnd` ISO 8601 ou null; cabeçalhos `Access-Control-Allow-Origin: *` e `Cache-Control: public, max-age=30`; rascunho → 404; slug desconhecido → 404 JSON) → FAIL.
- [ ] **Step 2: Implementar.** **Step 3: `bin/rails test`** → PASS. **Step 4: Commit** `feat: public JSON feeds for the stream kit`.

---

### Task 2: Produção com Kamal, backups e deploy por GitHub Actions

**Files:**
- Modify: `Dockerfile` (`ARG RUBY_VERSION=4.0.3`, `libvips`, `npm ci` só no build stage, `bin/rails tailwindcss:build` + `assets:precompile` no build), `config/deploy.yml` (serviço `grindin-station`, `image: ghcr.io/kakahpt/grindin-station`, `servers.web: [<%= ENV["GS_VPS_HOST"] %>]`, `proxy.host: <%= ENV["GS_DOMAIN"] %>`, `ssl: true`, `registry.server: ghcr.io`, `username: kakahpt`, `password: [KAMAL_REGISTRY_PASSWORD]`, `env.secret`: `RAILS_MASTER_KEY`, `PRIMARY_DATABASE_URL`, `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`; `env.clear`: `SOLID_QUEUE_IN_PUMA: true`, `RAILS_LOG_LEVEL: info`; `volumes: ["grindin_storage:/rails/storage"]`; `accessories.db`: `image: postgis/postgis:17-3.5`, `host: <%= ENV["GS_VPS_HOST"] %>`, `env.secret: [POSTGRES_PASSWORD]`, `directories: ["data:/var/lib/postgresql/data"]`, `files: ["config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql"]`; `accessories.backup`? → não: backups por cron no host, ver script), `.kamal/secrets` (ler de ENV: `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `PRIMARY_DATABASE_URL`… derivados com `$(...)`), `config/environments/production.rb` (`config.hosts << ENV["GS_DOMAIN"]`, `force_ssl` já, `active_storage.service = :local` com `config/storage.yml` `local.root: /rails/storage`, `action_mailer` com SMTP por ENV se existir), `config/cable.yml` (produção: solid_cable já), `.github/workflows/ci.yml` (nada) 
- Create: `config/postgres/init.sql` (`CREATE DATABASE` para `grindin_station_production`, `_cache`, `_queue`, `_cable` + `CREATE EXTENSION postgis, pgcrypto`), `bin/backup` (bash: `docker exec grindin-station-db pg_dump -Fc` para `/var/backups/grindin-station/<data>.dump`, manter 14, `rclone copy` se `RCLONE_REMOTE` definido; `set -euo pipefail`), `config/backup.cron` (linha para `crontab`: 04:00 diariamente), `.github/workflows/deploy.yml` (`on: workflow_run` do CI em `main` com `conclusion == success`, ou `on: push: branches: [main]` + `needs` via reutilização — escolher `workflow_run`; passos: checkout, ruby/setup-ruby com bundler-cache, `webfactory/ssh-agent` com `SSH_PRIVATE_KEY`, login ghcr com `GITHUB_TOKEN`, verificar que cada segredo necessário existe (passo bash que falha com a lista dos que faltam), `bin/kamal deploy`; `concurrency: deploy`), `docs/superpowers/notes/2026-11-04-m4-vps-checklist.md` (checklist manual: criar VPS Ubuntu 24.04 na Hostinger, abrir 22/80/443, DNS A `GS_DOMAIN` → IP, `ssh-keygen` e adicionar a chave ao VPS, segredos no GitHub: `SSH_PRIVATE_KEY`, `KAMAL_REGISTRY_PASSWORD` (= PAT `write:packages`), `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `GS_VPS_HOST`, `GS_DOMAIN`, OAuth; primeiro deploy à mão: `bin/kamal setup`; `bin/kamal app exec 'bin/rails db:seed'`; verificar `https://GS_DOMAIN/up`; instalar `bin/backup` no cron; testar restore)
- Test: `test/system`? não. `test/integration/health_test.rb` (`GET /up` → 200), script `bin/docker-smoke` (se `docker` existir: `docker build -t gs-smoke .` e `docker run --rm gs-smoke bin/rails runner 'puts Rails.env'`; senão imprime "docker not available" e sai 0), `bin/rails test`.

**Interfaces:**
- Produces: imagem construível, `config/deploy.yml` completo por ENV, `bin/backup`, `.github/workflows/deploy.yml`, checklist. Nenhum segredo no repositório (grep `-i "password\|secret"` nos ficheiros novos só deve encontrar nomes de variáveis).

- [ ] **Step 1: Testes** (`health_test`; teste de `bin/backup --dry-run` em `test/bin/backup_test.rb` via `system` que verifica a rotação com ficheiros fictícios num diretório temporário; verificar que `config/deploy.yml` faz parse com `ERB` + `YAML` com as ENV definidas para dummies — `test/config/deploy_config_test.rb`) → FAIL.
- [ ] **Step 2: Implementar.** **Step 3: `bin/rails test` + `bin/docker-smoke`** → PASS (ou "docker not available"). **Step 4: Commit** `ops: Kamal deploy config, Postgres accessory, backups, GitHub Actions deploy`.

---

### Task 3: Fecho do M4

- [ ] README: secção "Produção" (pt-PT, ~25 linhas: arquitectura, variáveis/segredos, primeiro deploy, deploy contínuo, backups e restore, feeds para o OBS com os três URLs e a nota de que o kit troca `const API` para `https://GS_DOMAIN/api/v1/events/<slug>/`), CLAUDE.md actualizado (API namespace, Kamal, backups).
- [ ] `bin/rubocop && bin/brakeman --no-pager -q && bin/rails test && bin/rails test:system` verdes.
- [ ] Commit `docs: production section; M4 code closed (VPS steps pending the user)`.

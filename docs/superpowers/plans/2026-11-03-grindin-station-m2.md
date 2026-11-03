# Grindin Station — Plano de implementação M2 (dia de torneio)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correr um torneio inteiro no dia: roster com check-in, lista de espera e drops; rondas com estados por mesa; resultados reportados por jogadores com confirmação configurável e contestação; chamada de juiz e Judge Center; fecho de ronda e corte com regra de tempo; timer em ecrã grande; impressões; staff por evento; tudo com o aspeto aprovado nos mockups.

**Architecture:** Rails 8.1 sobre o motor do M1. Novas tabelas (`event_staff`, `judge_calls`, `notifications`) e colunas de estado nos `pods`; a lógica de resultados fica em serviços `Results::*` que envolvem o `Events::SubmitResultJob` existente; páginas do jogador num namespace `play/` por slug; autorização por papel em `Organizer::OrganizerController`. O aspeto entra como tokens Tailwind 4 (`@theme`) e é aplicado às páginas que o M2 toca.

**Tech Stack:** Ruby 4.0.3, Rails 8.1, PostgreSQL 17 + PostGIS, Hotwire, Tailwind 4 + Flowbite, Solid Queue (recurring), `rqrcode` (novo, para os slips), Minitest + Capybara/Selenium headless Chrome (CI já instala `google-chrome-stable`).

**Spec:** `docs/superpowers/specs/2026-10-14-grindin-station-design.md` §4, §5.1 (regra de tempo do corte), §5.5, §5.6, §6 (papéis), §7, §9 (três fluxos), §10 M2. Mockups aprovados: tela "Grindin Station mockups" (paleta A grafite + teal, texto mínimo, comandantes opcionais, botão "Draw").

## Global Constraints

- `result_confirmation` ∈ `none | one | all`, predefinição `none`, **alterável a qualquer momento**; timeout em `one`/`all` com predefinição 5 min → pod passa a "a rever".
- Em `none` o resultado fecha o pod de imediato; os outros jogadores têm sempre "contestar", que marca `disputed` e abre uma chamada de juiz.
- Staff (organizer, judge, scorekeeper) pode sempre reportar, corrigir ou sobrepor-se. Papéis: organizer = tudo; judge = rondas, resultados, Judge Center, penalizações; scorekeeper = resultados e check-in.
- Ronda fecha só por clique do organizador ("Close round"), e só quando todas as mesas têm resultado (sem resultados pendentes de confirmação nem disputas abertas); fechar publica standings.
- Correção depois de fechado: só staff; o resultado antigo fica `superseded_by` o novo; se já há ronda seguinte publicada, exige confirmação explícita.
- Drops: antes de a ronda ser publicada saem do emparelhamento; depois, ficam na mesa com derrota e saem na seguinte. No-show no check-in = drop. Inscrição tardia só até o Swiss começar. Lista de espera quando `waitlist_enabled` e o máximo foi atingido; promoção automática por ordem quando alguém sai antes do início.
- Corte: regra de tempo `highest_seed_advances` (predefinição) ou `replay`; aplicada por staff ao clicar "Time called" numa mesa do corte.
- Comandantes só aparecem (standings, mesa, feeds) se `show_commanders_in_standings`.
- Timer público em `/t/:slug/timer` sem login; página do jogador `/t/:slug/me` com login.
- Paleta A: ground `#111315`, surface `#1b1e22`, line `#2a2f36`, ink `#eef0f2`, muted `#8b949e`, accent `#2dd4bf`, warn `#fbbf24`, danger `#f87171`; títulos Sora, corpo Manrope; uma só cor de destaque; sem texto explicativo sobre a justiça; botão de empate "Draw".
- Locales en (predefinição) + pt com paridade de chaves; rubocop-rails-omakase; commits com o trailer da sessão; nunca editar `docs/superpowers/plans|specs` dentro de uma tarefa.

## Review Focus

1. Dois jogadores da mesma mesa reportam resultados diferentes ao mesmo tempo: o segundo não pode sobrepor silenciosamente o primeiro — Task 5 testa "segundo reporte com valor diferente marca `disputed`".
2. Jogador que fez drop depois da ronda publicada ainda está na mesa: tem de contar como derrota e não aparecer na ronda seguinte — Task 3 testa.
3. Staff corrige um resultado de uma ronda já fechada com a ronda seguinte publicada: standings recalculam e a UI avisa — Task 4 testa a superseding e o aviso.
4. Timer e página do jogador com rede má: as páginas têm de funcionar sem JS além do relógio e nunca bloquear num pedido — Task 7 e Task 10 têm testes sem JS (integração) e o timer calcula localmente a partir de `started_at`.
5. Juiz sem conta de organizador tenta abrir o Judge Center: tem de entrar com o papel `judge` e nada mais — Task 2 testa cada papel contra cada página.

---

### Task 1: Definições do evento para o dia

**Files:**
- Create: `db/migrate/<ts>_add_day_settings_to_events.rb`
- Modify: `app/models/event.rb`, `app/controllers/organizer/tournaments_controller.rb` (`tournament_params`), `app/views/organizer/tournaments/_form.html.erb`, `config/locales/en.yml`, `config/locales/pt.yml`
- Test: `test/models/event_day_settings_test.rb`

**Interfaces:**
- Produces: colunas `events.self_report_enabled` (boolean, default true), `result_confirmation` (string, default "none"), `confirmation_timeout_minutes` (integer, default 5), `waitlist_enabled` (boolean, default false), `show_commanders_in_standings` (boolean, default false), `top_cut_timeout_rule` (string, default "highest_seed_advances"). `Event::RESULT_CONFIRMATIONS = %w[none one all]`, `Event::TOP_CUT_TIMEOUT_RULES = %w[highest_seed_advances replay]`, validações de inclusão; nenhum destes campos é bloqueado pelo estado.

- [ ] **Step 1: Teste**

```ruby
# test/models/event_day_settings_test.rb
require "test_helper"

class EventDaySettingsTest < ActiveSupport::TestCase
  test "defaults" do
    t = Tournament.new
    assert_equal [true, "none", 5, false, false, "highest_seed_advances"],
                 [t.self_report_enabled, t.result_confirmation, t.confirmation_timeout_minutes,
                  t.waitlist_enabled, t.show_commanders_in_standings, t.top_cut_timeout_rule]
  end

  test "confirmation can change mid-tournament" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    assert t.update(result_confirmation: "all")
    assert_not t.update(result_confirmation: "two")
  end
end
```

- [ ] **Step 2: Correr e ver falhar** — `bin/rails test test/models/event_day_settings_test.rb` → FAIL (atributo desconhecido).
- [ ] **Step 3: Implementar** migração, constantes, validações, campos no formulário (secção "Day of the event": select da confirmação, timeout, checkboxes, select da regra de tempo) com labels/ajudas em en e pt.
- [ ] **Step 4: `bin/rails test`** → PASS.
- [ ] **Step 5: Commit** `feat: day-of-event settings (self report, confirmation mode, waitlist, commanders, cut timeout rule)`.

---

### Task 2: Staff por evento e autorização por papel

**Files:**
- Create: `db/migrate/<ts>_create_event_staff.rb`, `app/models/event_staff.rb`, `app/controllers/organizer/staff_controller.rb`, `app/views/organizer/staff/index.html.erb`
- Modify: `app/models/user.rb` (`staff_role_for(event)`), `app/models/event.rb` (`has_many :event_staff`), `app/controllers/organizer/organizer_controller.rb`, `config/routes.rb`, `app/views/organizer/tournaments/_tournament_actions.html.erb` (ligação "Staff"), locales
- Test: `test/models/event_staff_test.rb`, `test/controllers/organizer/authorization_test.rb`

**Interfaces:**
- Produces: tabela `event_staff` (`event_id`, `user_id`, `role` string ∈ `EventStaff::ROLES = %w[organizer judge scorekeeper]`, único por `[event_id, user_id]`). `User#staff_role_for(event) -> String | nil` (o dono do evento, `event.event_organizer.user`, conta como "organizer" sem linha). `Organizer::OrganizerController#require_role(*roles)` como `before_action` parametrizável; `load_tournament` passa a aceitar eventos onde o user é staff (`Tournament.staffed_by(user)`). Matriz: organizer → tudo; judge → rounds (show/update results), results, infractions, judge_calls, event_participants index; scorekeeper → results, event_participants (index/update check-in e paid). Staff page: adicionar por e-mail de um user existente, remover.

- [ ] **Step 1: Testes** — `event_staff_test.rb`: `staff_role_for` devolve "organizer" para o dono, o papel da linha para staff, nil para outros; unicidade. `authorization_test.rb` (integração, usando `post session_url` com e-mail/palavra-passe do fixture ou do builder): para cada papel, GET à página de rondas (200 para organizer/judge, 302 para scorekeeper), ao Judge Center (criado na Task 6 — aqui testar só a rota de rondas e a edição do torneio: 200 só para organizer), PATCH check-in (200/302 OK para scorekeeper e organizer, recusado para judge).
- [ ] **Step 2: Correr e ver falhar.**
- [ ] **Step 3: Implementar** (ver Interfaces). `require_role` lê o evento de `params[:tournament_id] || params[:id]`.
- [ ] **Step 4: `bin/rails test`** → PASS.
- [ ] **Step 5: Commit** `feat: event staff roles (organizer, judge, scorekeeper) with per-page authorization`.

---

### Task 3: Roster do dia — check-in, no-show, drops, lista de espera, inscrição tardia

**Files:**
- Create: `db/migrate/<ts>_add_waitlist_and_drop_info_to_event_participants.rb`, `app/services/registrations/enroll.rb`, `app/services/registrations/drop.rb`
- Modify: `app/models/event_participant.rb`, `app/models/event.rb`, `app/controllers/organizer/event_participants_controller.rb`, `app/controllers/event_participants_controller.rb` (inscrição pública), `app/views/organizer/event_participants/index.html.erb` e `_event_participant.html.erb`, locales
- Test: `test/services/registrations/enroll_test.rb`, `test/services/registrations/drop_test.rb`, `test/controllers/organizer/roster_test.rb`

**Interfaces:**
- Produces: colunas `event_participants.waitlisted` (boolean default false), `waitlist_position` (integer), `dropped_at` (datetime), `drop_reason` (string ∈ `%w[drop no_show]`), `checked_in_at` (datetime).
- `Registrations::Enroll.call(event:, player:, decklist: nil) -> EventParticipant`: recusa se o Swiss começou (`Registrations::Closed`); se `waitlist_enabled` e `playing_participants_count >= maximum_participants`, cria com `waitlisted: true, waitlist_position: next`; senão inscrito normal.
- `Registrations::Drop.call(participant:, reason: "drop", by: user) -> EventParticipant`: marca `dropped`, `dropped_at`, `drop_reason`; se antes do início e há lista de espera, promove o primeiro (`waitlisted: false`, notificação na Task 6 via hook opcional). Depois de a ronda atual estar publicada, não toca na mesa (o jogador fica; `Round#event_participants` já exclui dropped na ronda seguinte); se a ronda atual não está publicada, a ronda é reconstruída (comportamento existente `rebuild_round`).
- Organizer roster: colunas Check-in (hora), Paid, Waitlist (posição), Dropped (motivo); ações: check-in/undo, mark paid/unpaid, drop, no-show, promote; contadores no topo (inscritos, checked-in, waitlist, dropped); filtro por estado; pesquisa.

- [ ] **Step 1: Testes** — enroll: fecha após swiss; waitlist quando cheio; posição crescente. drop: no-show marca `drop_reason: "no_show"`; promoção do primeiro da lista antes do início; depois da ronda publicada o jogador continua na mesa e tem `Loss` quando a mesa é reportada com outro vencedor; na ronda seguinte não é emparelhado. roster: scorekeeper consegue check-in; contadores corretos.
- [ ] **Step 2: Correr e ver falhar.** — [ ] **Step 3: Implementar.** — [ ] **Step 4: `bin/rails test`** → PASS. — [ ] **Step 5: Commit** `feat: day roster — check-in, no-show, drops with reasons, waitlist with promotion, late registration closed at swiss`.

---

### Task 4: Resultados imutáveis depois de fechados — superseding e correções

**Files:**
- Create: `db/migrate/<ts>_add_superseding_to_results.rb`, `app/services/results/apply.rb`
- Modify: `app/models/result.rb`, `app/models/event_participant.rb` (`results` exclui `superseded`), `app/models/pod.rb` (`results` idem), `app/jobs/events/submit_result_job.rb` (usa `Results::Apply`), `app/controllers/organizer/results_controller.rb` (confirmação quando há ronda seguinte publicada), `app/views/organizer/results/_form.html.erb`, locales
- Test: `test/services/results/apply_test.rb`, `test/controllers/organizer/result_correction_test.rb`

**Interfaces:**
- Produces: colunas `results.superseded_by_id` (uuid, nullable), `results.recorded_by_user_id` (uuid, nullable); índice único de `[event_participant_id, round_id]` passa a parcial `WHERE superseded_by_id IS NULL`. Scope `Result.current` (= `superseded_by_id: nil`); associações `results`/`opponents`/standings usam-no.
- `Results::Apply.call(pod:, type:, winner: nil, by: user_or_nil) -> Array<Result>`: se a ronda **não** está fechada, comporta-se como hoje (`create_or_update_by`); se está fechada (`finished_at`), cria resultados novos para a mesa e marca os antigos com `superseded_by`. Devolve `warning: :later_round_published` quando `event.rounds` tem ronda com número superior já publicada.
- Organizer: formulário de resultado numa ronda fechada mostra o aviso e exige `confirm=1`.

- [ ] **Step 1: Testes** — apply: ronda aberta → update in place; ronda fechada → novos resultados, antigos superseded, `match_points` recalcula; aviso quando ronda seguinte publicada; `EventParticipant#results.count` não conta superseded. controller: POST sem `confirm` numa ronda fechada com ronda seguinte publicada → 422 com mensagem; com `confirm=1` → aplica.
- [ ] **Step 2–5:** falhar, implementar, PASS, commit `feat: results are superseded, never overwritten, once a round is closed; staff corrections warn when a later round is published`.

---

### Task 5: Reporte pelos jogadores — confirmação configurável, contestação, timeout

**Files:**
- Create: `db/migrate/<ts>_add_reporting_state_to_pods.rb`, `app/services/results/report.rb`, `app/services/results/confirm.rb`, `app/services/results/contest.rb`, `app/jobs/results/expire_pending_job.rb`
- Modify: `app/models/pod.rb` (`report_status`), `config/recurring.yml` (job a cada minuto), locales
- Test: `test/services/results/report_test.rb`, `test/services/results/confirm_test.rb`, `test/services/results/contest_test.rb`, `test/jobs/results/expire_pending_job_test.rb`

**Interfaces:**
- Produces: colunas `pods.pending_result` (jsonb, nullable: `{"type":"Win","winner_id":"…"}` ou `{"type":"Draw"}`), `reported_by_participant_id` (uuid), `reported_at` (datetime), `confirmations` (jsonb default `{}`: participant_id → ISO time), `disputed` (boolean default false), `review_requested_at` (datetime).
- `Pod#report_status -> Symbol` ∈ `:playing` (sem nada), `:pending` (pending_result e faltam confirmações), `:review` (timeout), `:disputed`, `:completed` (resultados atuais para todos).
- `Results::Report.call(pod:, participant:, type:, winner: nil) -> Pod`: exige `event.self_report_enabled`, participante da mesa, mesa sem resultado completo; `none` → `Results::Apply` imediato, `reported_by/at` gravados; `one`/`all` → grava `pending_result`, `confirmations = {participant => now}`. Um segundo reporte **diferente** por outro jogador enquanto pendente → `disputed: true` (Review Focus 1); igual → conta como confirmação.
- `Results::Confirm.call(pod:, participant:)`: acrescenta confirmação; `one`: com 2 confirmações aplica; `all`: com `pod.size` confirmações aplica.
- `Results::Contest.call(pod:, participant:, reason:)`: só depois de aplicado ou pendente; `disputed: true`; abre a chamada com `JudgeCalls::Open` (Task 6). **Ordem de execução: 1, 2, 3, 4, 6, 5, 7, 8, 9, 10, 11, 12, 13, 14** — a Task 6 corre antes desta.
- `Results::ExpirePendingJob`: pods com `pending_result` e `reported_at < confirmation_timeout_minutes.ago` → `review_requested_at = now`. Agendado em `config/recurring.yml` a cada minuto.

- [ ] **Step 1: Testes** — report: `none` aplica logo e grava quem reportou; `one` fica pendente; segundo reporte diferente → disputed; `self_report_enabled: false` → erro. confirm: `one` aplica à 2ª; `all` só à 4ª (mesa de 4) e à 3ª numa mesa de 3. contest: marca disputed e cria judge_call com a razão. expire: só pods além do timeout passam a `:review`.
- [ ] **Step 2–5:** falhar, implementar, PASS, commit `feat: player result reporting with none/one/all confirmation, contest and review timeout`.

---

### Task 6: Chamadas de juiz, notificações e Judge Center

**Files:**
- Create: `db/migrate/<ts>_create_judge_calls_and_notifications.rb`, `app/models/judge_call.rb`, `app/models/notification.rb`, `app/services/judge_calls/open.rb`, `app/services/notify.rb`, `app/controllers/organizer/judge_calls_controller.rb`, `app/views/organizer/judge_calls/index.html.erb`
- Modify: `app/models/user.rb` (`has_many :notifications`), `config/routes.rb`, `app/views/organizer/tournaments/_tournament_actions.html.erb` (ligação "Judge Center" com contagem), locales
- Test: `test/models/judge_call_test.rb`, `test/services/notify_test.rb`, `test/controllers/organizer/judge_center_test.rb`

**Interfaces:**
- Produces: `judge_calls` (`event_id`, `pod_id` nullable, `event_participant_id` nullable, `reason` text, `status` string ∈ `%w[open acknowledged closed]` default open, `acknowledged_by_user_id`, `closed_at`, timestamps). `notifications` (`user_id`, `kind` string, `subject_type/subject_id`, `read_at`, timestamps).
- `JudgeCalls::Open.call(event:, pod: nil, participant: nil, reason:) -> JudgeCall` + `Notify.staff(event, kind: "judge_call", subject:)` (uma notificação por membro do staff com papel organizer/judge). `Notify.participants(pod, kind:, subject:)` para `result_pending`/`result_contested`/`round_published`.
- Judge Center: lista de chamadas abertas (mesa, jogador, razão, há quanto tempo), ações acknowledge/close; penalizações existentes ligadas abaixo (reutiliza a página de infrações).

- [ ] **Step 1: Testes** — judge_call: transições open→acknowledged→closed; Notify cria uma linha por staff; judge consegue ver e fechar; scorekeeper não entra (302).
- [ ] **Step 2–5:** falhar, implementar, PASS, commit `feat: judge calls, generic notifications and the Judge Center`.

---

### Task 7: Páginas do jogador — a minha mesa, reportar, confirmar, contestar, chamar juiz

**Files:**
- Create: `app/controllers/play/base_controller.rb`, `app/controllers/play/tables_controller.rb`, `app/controllers/play/reports_controller.rb`, `app/controllers/play/judge_calls_controller.rb`, `app/views/play/tables/show.html.erb`, `app/views/play/reports/new.html.erb`, `app/views/layouts/play.html.erb`
- Modify: `config/routes.rb` (`scope "/t/:slug", module: :play, as: :play`), locales
- Test: `test/controllers/play/tables_test.rb`, `test/controllers/play/reports_test.rb`

**Interfaces:**
- Produces rotas: `GET /t/:slug/me` (mesa atual: ronda, mesa, o meu assento, jogadores por ordem com comandantes se `show_commanders_in_standings`, estado do reporte, botões), `GET /t/:slug/pods/:id/report/new`, `POST …/report` (`type`, `winner_id`), `POST …/confirm`, `POST …/contest` (`reason`), `POST /t/:slug/judge_calls` (`reason`, pod implícito). `Play::BaseController` exige login e que `current_user.player` seja participante não eliminado do evento; sem ronda publicada mostra "waiting for pairings".
- Copy fixa: botões "Report result", "Draw", "Submit", "Call a judge", "Confirm", "Contest" (pt: "Reportar resultado", "Empate"… — **exceção**: o botão de empate é "Draw" também em pt por decisão do utilizador). Sem textos sobre justiça de assentos.

- [ ] **Step 1: Testes (integração, sem JS)** — jogador vê a mesa com o seu assento marcado; não-participante → 302; reportar em `none` fecha a mesa e a página mostra "Completed"; em `one` mostra "Waiting for confirmation" e outro jogador consegue confirmar; contestar marca disputed e cria judge_call; chamar juiz cria judge_call com a mesa; `?locale=pt` renderiza.
- [ ] **Step 2–5:** falhar, implementar (layout `play` mobile-first com os tokens da Task 12 — se a Task 12 ainda não correu, usar classes Tailwind neutras e deixar a Task 12 trocar), PASS, commit `feat: player pages — my table, report/confirm/contest, call a judge`.

---

### Task 8: Ronda do organizador — estados por mesa, fechar ronda, nova ronda

**Files:**
- Modify: `app/controllers/organizer/rounds_controller.rb` (`update` action "finish" → `close` com validação), `app/models/round.rb` (`closable?`, `blocking_pods`), `app/views/organizer/rounds/show.html.erb`, `app/views/organizer/pods/_pod.html.erb` (chip de estado: Completed / Playing / Pending / Review / Disputed / Judge called; "Reported by seat N · hh:mm"; botões Winner por assento e Draw; tempo extra), `app/helpers/tournaments_helper.rb`, locales
- Test: `test/controllers/organizer/round_close_test.rb`

**Interfaces:**
- Produces: `Round#closable? -> Boolean` (todas as mesas `:completed`), `Round#blocking_pods -> Array<Pod>`; `PATCH …/rounds/:id` com `round[action]=close` fecha (finished_at) só se `closable?`, senão 422 com a lista das mesas; depois de fechada mostra "New round" (Swiss seguinte) ou "Make cut" (última ronda Swiss, transição `single_elimination`) conforme `rounds_info`.
- O organizador pode reportar/alterar resultado em qualquer mesa (sobrepõe pendentes/disputas: limpa `pending_result`, `disputed`, fecha judge_calls da mesa).

- [ ] **Step 1: Testes** — close recusado com uma mesa pendente (422, nome da mesa na resposta); close OK quando tudo completo e standings ficam publicados (`finished_at`); reporte do staff numa mesa disputada limpa a disputa e fecha a chamada; "Make cut" aparece só na última ronda Swiss.
- [ ] **Step 2–5:** falhar, implementar, PASS, commit `feat: organizer round page — table states, close round guard, next round / make cut`.

---

### Task 9: Corte — "Time called" e regra de tempo

**Files:**
- Create: `app/services/results/timeout.rb`
- Modify: `app/controllers/organizer/results_controller.rb` (ação `timeout`), `config/routes.rb`, `app/views/organizer/pods/_pod.html.erb` (botão "Time called" só em `SingleEliminationRound`), locales
- Test: `test/services/results/timeout_test.rb`

**Interfaces:**
- Produces: `Results::Timeout.call(pod:, by: user) -> Pod`: em `highest_seed_advances` aplica `Advance` ao jogador com melhor `rank_score` da mesa e `Eliminated` aos outros (via `Results::Apply`); em `replay` não aplica nada e grava `pods.extra_time += event.top_cut_round_minutes / 2` (ronda de desempate) — e marca a mesa `review_requested_at` para o staff decidir manualmente. Só em rondas de eliminação, senão `ArgumentError`.

- [ ] **Step 1: Testes** — highest seed avança; replay dá tempo extra e nada mais; Swiss → ArgumentError.
- [ ] **Step 2–5:** commit `feat: top-cut time called applies the event's timeout rule`.

---

### Task 10: Timer em ecrã grande

**Files:**
- Create: `app/controllers/play/timers_controller.rb`, `app/views/play/timers/show.html.erb`, `app/javascript/controllers/big_timer_controller.js`
- Modify: `config/routes.rb` (`GET /t/:slug/timer`, sem login), locales
- Test: `test/controllers/play/timer_test.rb`

**Interfaces:**
- Produces: página só com o nome do evento, o nome da ronda e o relógio (mm:ss, vermelho a partir de 0, continua a contar o excesso), lendo `round.started_at` e `event.round_minutes`/`top_cut_round_minutes` por `data-*`; sem ronda iniciada mostra "Waiting"; `<meta http-equiv="refresh" content="30">` para apanhar novas rondas sem JS. Fundo `ground`, dígitos Sora ≥ 20 vh.

- [ ] **Step 1: Teste** — 200 sem login; mostra a ronda atual e os `data-started-at`/`data-round-minutes`; sem ronda → "Waiting".
- [ ] **Step 2–5:** commit `feat: public big-screen timer`.

---

### Task 11: Impressões — emparelhamentos A4 e slips por mesa com QR

**Files:**
- Modify: `Gemfile` (`gem "rqrcode"`), `config/routes.rb`, `app/controllers/organizer/rounds_controller.rb` (ações `print` e `slips`), locales
- Create: `app/views/organizer/rounds/print.html.erb`, `app/views/organizer/rounds/slips.html.erb`, `app/assets/stylesheets/print.css` (`@media print`)
- Test: `test/controllers/organizer/print_test.rb`

**Interfaces:**
- Produces: `GET …/rounds/:id/print` — lista por mesa (nº, 4 jogadores por ordem de assento, comandante se ativo), 2 colunas, quebra de página a cada 20 mesas, cabeçalho com evento e ronda; `GET …/rounds/:id/slips` — um cartão por mesa (A4 com 6 slips) com QR para `play_table_url(slug)` (a página do jogador) e os nomes por assento. QR gerado com `RQRCode::QRCode.new(url).as_svg`.

- [ ] **Step 1: Teste** — print lista todas as mesas e assentos na ordem; slips contém um `<svg` por mesa e o URL em texto.
- [ ] **Step 2–5:** commit `feat: printable pairings and table slips with QR codes`.

---

### Task 12: Aspeto — tokens da paleta A e aplicação às páginas do M2

**Files:**
- Modify: `app/assets/tailwind/application.css` (`@theme { --color-ground … --font-display: Sora; --font-body: Manrope }`, importação Google Fonts no layout), `app/views/layouts/application.html.erb` e `app/views/layouts/play.html.erb` (nav neutra, fundo `ground`, texto `ink`), `app/views/organizer/rounds/show.html.erb`, `app/views/organizer/pods/_pod.html.erb`, `app/views/organizer/event_participants/index.html.erb`, `app/views/organizer/judge_calls/index.html.erb`, `app/views/play/**`, `app/views/event_participants/index.html.erb` (standings), `app/views/tournaments/_standings_help.html.erb`
- Test: `test/integration/branding_test.rb` (acrescentar: a página de standings usa a classe `bg-ground`; nenhuma classe `purple`/`orange` nas páginas do M2 — `assert_no_match(/bg-(purple|orange)-/, response.body)`)

**Interfaces:**
- Produces: classes utilitárias `bg-ground bg-surface border-line text-ink text-muted bg-accent text-accent bg-warn bg-danger font-display font-body`; chips de estado: completed = accent, pending/review = muted, judge called = warn, disputed = danger. Comandantes nas páginas só com `show_commanders_in_standings`. Mesmo layout das pranchas aprovadas: cartão mesa/assento grande, lista 1–4, botões cheios de 52 px.

- [ ] **Step 1: Teste** (branding) → FAIL. — [ ] **Step 2: Implementar.** — [ ] **Step 3: `bin/rails test`** → PASS. — [ ] **Step 4: Commit** `feat: palette A tokens applied to organizer round, roster, judge center, player and standings pages`.

---

### Task 13: Testes de sistema dos três fluxos e CI com browser

**Files:**
- Modify: `test/application_system_test_case.rb` (`driven_by :selenium, using: :headless_chrome, screen_size: [390, 844]` para os fluxos de jogador e `[1280, 960]` para o organizador), `.github/workflows/ci.yml` (`bin/rails test:system` de volta, `google-chrome-stable` já instalado)
- Create: `test/system/organizer_round_flow_test.rb`, `test/system/player_report_flow_test.rb`, `test/system/close_round_and_cut_test.rb`

**Interfaces:**
- Fluxo 1: organizador cria evento (16 jogadores via builder), abre inscrições, fecha, começa Swiss, publica ronda 1, vê as 4 mesas com assentos. Fluxo 2: jogador entra, vê a mesa, reporta vitória (`none`), a mesa fica Completed; outro jogador contesta; o Judge Center mostra a chamada. Fluxo 3: organizador reporta as restantes mesas, fecha a ronda (guard), ronda 2, … , "Make cut", corte com assentos por classificação, "Time called" aplica a regra.

- [ ] **Step 1: Escrever os três testes** (Capybara, seletores por texto dos botões fixados na Task 7/8).
- [ ] **Step 2: `bin/rails test:system`** localmente (instalar Chrome se faltar: `brew install --cask google-chrome`; o `selenium-webdriver` gere o driver) → PASS.
- [ ] **Step 3: CI** — repor `test:system` no job `test`; `gh run watch` verde.
- [ ] **Step 4: Commit** `test: system tests for the three tournament-day flows; CI runs them headless`.

---

### Task 14: Fecho do M2

- [ ] README: secção "Dia de torneio" (pt-PT, ~30 linhas: papéis, confirmação, contestação, fecho de ronda, corte e regra de tempo, timer, impressões, páginas do jogador em `/t/:slug/me`); CLAUDE.md atualizado.
- [ ] `bin/rubocop && bin/brakeman --no-pager -q && bin/rails test && bin/rails test:system && bin/rails "grindin:simulate[500]"` verdes; push do ramo `m2`; CI verde.
- [ ] Commit `docs: tournament-day section; M2 closed`.

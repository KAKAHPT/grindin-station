# Grindin Station — Plano de implementação M3 (jogadores e público)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O jogador entra com Google ou Discord, vê a sua mesa a actualizar ao vivo, tem um perfil público com histórico e assentos, e o público vê o evento, os inscritos, a lista de espera, as mesas da ronda e as standings sem login — tudo em páginas mobile rápidas.

**Architecture:** Rails 8.1 sobre o M2. OmniAuth com uma tabela `identities` (várias identidades por user, ligação por e-mail igual). "Ao vivo" por Turbo Streams: os modelos `Pod`, `Round` e `JudgeCall` emitem `broadcast_replace_later_to` para um stream por evento, e as páginas do jogador e do organizador subscrevem com `turbo_stream_from`; sem JS próprio além do Turbo. Perfis em `/p/:handle` e páginas públicas do evento em `/t/:slug/...` no layout `play` (sem login) reutilizando os parciais do M2. Notificações ganham uma página e um contador.

**Tech Stack:** Ruby 4.0.3, Rails 8.1, PostgreSQL 17, Hotwire (Turbo Streams sobre Action Cable: `async` em dev, `test` em test, Solid Cable em produção), Tailwind 4, `omniauth`, `omniauth-google-oauth2`, `omniauth-discord`, `omniauth-rails_csrf_protection`, Active Storage (disco) + `image_processing` para avatares, Lighthouse CLI (`npx lighthouse`) para a verificação do marco.

**Spec:** `docs/superpowers/specs/2026-10-14-grindin-station-design.md` §6 (contas, papéis, perfil), §7 (jogador, público), §9, §10 M3. Decisões do M2 mantêm-se (paleta A, texto mínimo, "Draw", comandantes opcionais, botões quadrados, sem discos de ranking).

## Global Constraints

- Login: e-mail + palavra-passe (existente), Google e Discord via OmniAuth; uma conta pode ter várias identidades; ligação automática quando o e-mail do provider é igual ao da conta; ligação manual na página de conta. Credenciais por variáveis de ambiente `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`; sem elas os botões não aparecem (nunca rebentar). Em test usa-se `OmniAuth.config.test_mode` com mocks.
- Eliminação de conta = anonimização: nome passa a "Jogador removido", e-mail substituído por `deleted-<uuid>@removed.invalid`, palavra-passe e identidades apagadas, sessões destruídas, `users.anonymized_at` preenchido; `players`, `event_participants` e resultados ficam.
- Perfil público em `/p/:handle`: `handle` único (a-z0-9-), 3–30 chars, gerado do nome na criação da conta e editável; `visibility` ∈ `public | participants | private` (predefinição `public`); decklist de um evento só aparece se `events.show_decklists` (novo booleano, predefinição false) **e** o evento estiver `finished`.
- Ao vivo: a página "a minha mesa" e a página da ronda do organizador actualizam sem recarregar quando a ronda é publicada, um resultado entra, um reporte muda de estado ou uma chamada de juiz é reconhecida; a página continua correcta sem WebSocket (o HTML servido é sempre o estado actual).
- Público sem login: evento, inscritos + lista de espera, mesas da ronda actual, standings, resultados finais. Nunca decklists por aqui; comandantes só com `show_commanders_in_standings`.
- Mobile first nas páginas de jogador e públicas: 375 px sem scroll horizontal; Lighthouse mobile ≥ 90 em performance e acessibilidade em `/t/:slug`, `/t/:slug/standings`, `/t/:slug/pairings` e `/p/:handle`.
- Locales en (predefinição) + pt com paridade de chaves; rubocop-rails-omakase; Brakeman limpo; commits com o trailer da sessão; nunca editar `docs/superpowers/plans|specs` dentro de uma tarefa.

## Review Focus

1. Login Google com um e-mail que já tem conta por palavra-passe: tem de entrar na mesma conta, não criar outra — Task 1 testa.
2. Utilizador anonimizado: as standings antigas continuam a somar os pontos dele e o nome aparece "Jogador removido"; o handle fica livre — Task 2 testa.
3. Perfil `participants`: só quem partilhou um evento com o jogador o vê; `private`: só o próprio — Task 3 testa cada caso.
4. Broadcast de uma mesa quando um resultado é corrigido depois da ronda fechada: a página do jogador mostra o novo estado e não o antigo — Task 4 testa o broadcast após `Results::Apply` em ronda fechada.
5. Página pública das mesas numa ronda com byes e mesas de 3/5: todos os jogadores aparecem exactamente uma vez — Task 6 testa.

---

### Task 1: Identidades OmniAuth (Google e Discord)

**Files:**
- Modify: `Gemfile` (`omniauth`, `omniauth-google-oauth2`, `omniauth-discord`, `omniauth-rails_csrf_protection`), `config/initializers/omniauth.rb` (create), `config/routes.rb`, `app/views/sessions/new.html.erb`, `app/models/user.rb`, `config/locales/{en,pt}.yml`, `test/test_helper.rb` (mocks)
- Create: `db/migrate/<ts>_create_identities.rb`, `app/models/identity.rb`, `app/controllers/omniauth_callbacks_controller.rb`, `app/services/accounts/connect_identity.rb`
- Test: `test/models/identity_test.rb`, `test/services/accounts/connect_identity_test.rb`, `test/controllers/omniauth_callbacks_controller_test.rb`

**Interfaces:**
- Produces: tabela `identities` (`user_id` FK não nulo, `provider` string, `uid` string, `email` string, `name` string, timestamps; índice único `[provider, uid]`). `Identity belongs_to :user`; `User has_many :identities, dependent: :destroy`. `Accounts::ConnectIdentity.call(auth:, current_user: nil) -> User` (regras: identidade existente → o seu user; senão `current_user` se houver; senão user com `email_address == auth.info.email` normalizado; senão cria user com nome do provider e palavra-passe aleatória; em todos os casos cria a `Identity`). Rotas `GET /auth/:provider/callback` → `omniauth_callbacks#create`, `GET /auth/failure` → `#failure`. `OmniauthHelper#oauth_enabled?(provider)` verifica as env vars. `User.anonymized` scope para a Task 2.

- [ ] **Step 1: Testes** (`connect_identity_test.rb`: "identidade conhecida devolve o seu user", "e-mail igual liga à conta existente sem criar user", "e-mail novo cria user e player", "com current_user liga a esse user mesmo com e-mail diferente"; `omniauth_callbacks_controller_test.rb` com `OmniAuth.config.mock_auth[:google_oauth2]`: cria sessão e redirecciona para `after_authentication_url`; `failure` redirecciona para `new_session_path` com alerta) → FAIL.
- [ ] **Step 2: Implementar** (initializer com `provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]` e `:discord` com scope `identify email`; `OmniAuth.config.allowed_request_methods = [:post]`; botões "Continue with Google / Discord" na página de sessão só quando `oauth_enabled?`; o callback usa `start_new_session_for`).
- [ ] **Step 3: `bin/rails test`** → PASS. **Step 4: Commit** `feat: sign in with Google and Discord (identities)`.

---

### Task 2: Página de conta, identidades ligadas e eliminação com anonimização

**Files:**
- Create: `db/migrate/<ts>_add_profile_fields_to_users.rb` (`handle` string único, `country` string(2), `bio` text, `visibility` string default "public", `anonymized_at` datetime), `app/controllers/accounts_controller.rb`, `app/views/accounts/show.html.erb`, `app/services/accounts/anonymize.rb`
- Modify: `app/models/user.rb` (`has_one_attached :avatar`, validações de `handle`/`visibility`, geração do handle em `before_validation on: :create`, `display_name`), `app/models/player.rb` (`name` usa `user.display_name`), `config/routes.rb` (`resource :account, only: %i[show update destroy]`; `delete /account/identities/:id`), layouts (link "Account" na nav), locales
- Test: `test/models/user_handle_test.rb`, `test/services/accounts/anonymize_test.rb`, `test/controllers/accounts_controller_test.rb`

**Interfaces:**
- Produces: `User#handle` (gerado: parametrize do nome, sufixo `-2`, `-3`… até ser único), `User::VISIBILITIES = %w[public participants private]`, `User#display_name` ("Jogador removido" / "Removed player" por locale quando `anonymized_at`), `Accounts::Anonymize.call(user:)` (regras das Global Constraints; devolve o user), página `/account` com nome, e-mail, palavra-passe, handle, país, bio, visibilidade, avatar (JPEG/PNG/WebP ≤ 2 MB, variante 96×96 e 256×256), identidades ligadas (com "desligar" só quando sobra palavra-passe ou outra identidade) e "Eliminar conta" com confirmação por texto.

- [ ] **Step 1: Testes** (handle: "Fábio Batista" → `fabio-batista`, colisão → `fabio-batista-2`, edição inválida rejeitada; anonymize: nome/e-mail/identities/sessions como nas constraints, `rank_score` do participant inalterado, `handle` libertado (passa a nil); controller: update do perfil, upload de avatar, destroy chama `Anonymize` e termina a sessão) → FAIL.
- [ ] **Step 2: Implementar** (`image_processing` no Gemfile; Active Storage já migrado). **Step 3: `bin/rails test`** → PASS. **Step 4: Commit** `feat: account page with linked identities, profile fields and anonymised deletion`.

---

### Task 3: Perfil público `/p/:handle`

**Files:**
- Create: `app/controllers/profiles_controller.rb`, `app/views/profiles/show.html.erb`, `app/views/profiles/_event_row.html.erb`, `app/queries/profiles/history.rb`
- Modify: `db/migrate/<ts>_add_show_decklists_to_events.rb` (`events.show_decklists` boolean default false), `app/views/organizer/tournaments/_form.html.erb` (toggle), `config/routes.rb` (`get "/p/:handle", to: "profiles#show", as: :profile`), `app/views/layouts/play.html.erb` (nome do jogador linka para o perfil), `app/views/event_participants/_event_participant.html.erb` (nome linka para o perfil quando visível), locales
- Test: `test/controllers/profiles_controller_test.rb`, `test/queries/profiles/history_test.rb`

**Interfaces:**
- Consumes: `User#handle`, `visibility`, `display_name`, avatar (Task 2); `EventParticipant#seat_counts`, `final_position` (M1), `decklist`.
- Produces: `Profiles::History.call(user:) -> [Row(event:, position:, participants:, wins:, losses:, draws:, seats:, decklist_visible:)]` ordenado por data desc, só eventos `finished`; `ProfilesController#show` aplica `visibility` (`public` sempre; `participants` quando `current_user` partilha pelo menos um evento ou é o próprio; `private` só o próprio) → 404 caso contrário (nunca revelar a existência). Layout `play`-like sem evento: cabeçalho com avatar, nome, handle, país, bio; lista de eventos com posição "3.º de 32", W-L-D e a grelha de assentos; lugares reservados (sem funcionalidade) para "Seguir" e comentários conforme a spec §6.

- [ ] **Step 1: Testes** (history: evento finished aparece, evento em swiss não; decklist só com `show_decklists` e finished; visibilidade: três casos × anónimo/participante/próprio) → FAIL. **Step 2: Implementar.** **Step 3: `bin/rails test`** → PASS. **Step 4: Commit** `feat: public player profiles`.

---

### Task 4: "A minha mesa" e página da ronda ao vivo (Turbo Streams)

**Files:**
- Create: `app/models/concerns/live_broadcasts.rb`, `app/jobs/live/broadcast_pod_job.rb` (ou usar `broadcast_replace_later_to`), `app/views/play/tables/_table.html.erb` (extraído de `show.html.erb`), `app/views/organizer/pods/_pod_frame.html.erb` (wrapper com id estável)
- Modify: `app/models/pod.rb`, `app/models/round.rb`, `app/models/judge_call.rb` (after_commit → broadcasts), `app/views/play/tables/{show,waiting,bye}.html.erb` (`turbo_stream_from current_event, current_participant`), `app/views/organizer/rounds/show.html.erb` (`turbo_stream_from round`), `app/services/results/apply.rb` (garantir broadcast após supersede em ronda fechada), `config/cable.yml` (dev continua `async`)
- Test: `test/models/pod_broadcast_test.rb`, `test/integration/live_table_test.rb`, `test/system/live_table_test.rb` (Chrome: dois contextos — jogador vê o estado mudar quando o staff regista o resultado, sem recarregar)

**Interfaces:**
- Consumes: `Pod#report_status`, `Results::Apply`, `Round#published`, `JudgeCall` estados (M2).
- Produces: streams `"event:<event_id>:participant:<ep_id>"` (um por participante da mesa; o parcial `_table` é re-renderizado com o `current_participant` certo, por isso o broadcast é feito por participante) e `"round:<round_id>"` (substitui `#pod_<id>` pelo parcial do organizador com `staff_role: "organizer"` — ver nota). Nota de segurança: o parcial do organizador contém botões de staff; o stream `round:<id>` só é assinado para quem já está na página do organizador (o `turbo_stream_from` é assinado) e o cartão emitido não deve variar por papel — se variar, emitir apenas a parte de estado (chips e linhas) e deixar os botões ao HTML servido. Gatilhos: `Round` `published` true → cada participante recebe a sua mesa; `Pod` mudança em `report_status`-relevantes (`pending_result`, `confirmations`, `disputed`, `review_requested_at`, `extra_time`) e novos `results` → mesa + cartão; `JudgeCall` muda de estado → mesa.

- [ ] **Step 1: Testes** (`assert_turbo_stream_broadcasts` ao publicar a ronda, ao aplicar um resultado, ao reconhecer uma chamada; integração: o HTML de `/t/:slug/me` contém `turbo-cable-stream-source` com o nome do stream assinado; sistema: dois browsers) → FAIL. **Step 2: Implementar** (`broadcast_replace_later_to`, Solid Queue em test corre inline). **Step 3: `bin/rails test && bin/rails test:system`** → PASS. **Step 4: Commit** `feat: live updates for my table and the organizer round page`.

---

### Task 5: Página pública do evento e notificações

**Files:**
- Modify: `app/controllers/tournaments_controller.rb` (`show` no layout `play` por slug: `GET /t/:slug` → `play/events#show` com `allow_unauthenticated_access`), `config/routes.rb`, `app/views/play/events/show.html.erb` (create: descrição em markdown, local com mapa só se houver coordenadas, data/hora, preço com moeda, regras, estado, contadores, botão Inscrever/Anular ou "Entrar para inscrever-se", lista de inscritos e lista de espera com posições), `app/views/tournaments/show.html.erb` (redirecciona para `/t/:slug`), `app/views/layouts/play.html.erb` (nav: Event · Pairings · Standings · My table; "My table" só com login e inscrição; sino de notificações com contador)
- Create: `app/controllers/notifications_controller.rb` (`index`, `mark_all_read`), `app/views/notifications/index.html.erb`, `app/views/play/events/_enrolled.html.erb`
- Test: `test/controllers/play/events_controller_test.rb`, `test/controllers/notifications_controller_test.rb`

**Interfaces:**
- Consumes: `Event#fill_from_waitlist!`, `enrolled`/waitlisted scopes, `Notify` (M2), `Registrations::Enroll/Drop`.
- Produces: rota pública `GET /t/:slug` (`play_event_path`), `GET /notifications`, `POST /notifications/mark_all_read`; `Play::BaseController` passa a aceitar visitantes nas acções públicas (`public_actions` como no organizer) e só exige participante nas acções de jogador. `User#unread_notifications_count`. Chips de estado do evento (Registration open · Closed · Swiss R3 · Top 16 · Finished).

- [ ] **Step 1: Testes** (página pública sem login mostra inscritos e lista de espera com posições e nunca decklists; com login e inscrição mostra "Anular"; notificações: lista, contador, marcar lidas; "the table is told" da contestação aparece aos jogadores da mesa) → FAIL. **Step 2: Implementar.** **Step 3: `bin/rails test`** → PASS. **Step 4: Commit** `feat: public event page, waitlist in public, notifications page`.

---

### Task 6: Mesas da ronda e standings públicas em `/t/:slug/...`

**Files:**
- Create: `app/controllers/play/pairings_controller.rb`, `app/views/play/pairings/show.html.erb`, `app/views/play/pairings/_table.html.erb`
- Modify: `config/routes.rb` (`GET /t/:slug/pairings`, `GET /t/:slug/standings` → `event_participants#index` já existente, em layout `play`), `app/views/layouts/play.html.erb` (nav), `app/views/event_participants/index.html.erb` (resultados finais quando `finished`: Top N com posição; "Final" no título), `app/views/play/tables/_table.html.erb` (reutilizar o parcial de mesa pública para a lista de nomes)
- Test: `test/controllers/play/pairings_controller_test.rb`, `test/integration/public_pages_mobile_test.rb` (cada página pública a 375 px não tem elementos mais largos que o viewport — verificar por classes `overflow-x-auto`/`max-w` e, no sistema, `page.evaluate_script("document.documentElement.scrollWidth <= 375")`)

**Interfaces:**
- Consumes: `Round` publicada, `Pod#report_status`, `seatings` ordenadas, `show_commanders_in_standings`, Turbo stream `round:<id>` (Task 4) — a página pública subscreve o mesmo stream mas o parcial público não tem botões.
- Produces: `GET /t/:slug/pairings` (ronda actual: mesas com número, estado, 4 lugares por ordem, vencedor marcado, byes listados; selector de ronda `?round=N` para rondas fechadas), `GET /t/:slug/standings`; a nav do jogador usa estas rotas. Review Focus 5: cada jogador da ronda aparece exactamente uma vez (byes incluídos).

- [ ] **Step 1: Testes** → FAIL. **Step 2: Implementar.** **Step 3: `bin/rails test && bin/rails test:system`** → PASS. **Step 4: Commit** `feat: public pairings and standings under /t/:slug`.

---

### Task 7: Performance mobile (Lighthouse ≥ 90)

**Files:**
- Modify: `app/views/layouts/play.html.erb` e `application.html.erb` (fontes: `<link rel="preload">` só das duas faces usadas, `font-display: swap`; Phosphor Icons: substituir o CSS do CDN por um sprite SVG local `app/assets/images/icons.svg` com os ~20 ícones usados e um helper `icon(name)` que emite `<svg><use href="...#name">`; `meta name="theme-color" content="#111315"`; `lang`, `viewport`, `description`), `app/helpers/application_helper.rb` (`icon`), `config/importmap.rb` (flowbite só nas páginas do organizador: mover o `import "flowbite"` para um `organizer.js` carregado apenas no layout `application`), `app/assets/tailwind/application.css` (sem `@import` de Flowbite nas páginas `play` se for separável; senão manter)
- Create: `lib/tasks/lighthouse.rake` (`bin/rails "grindin:lighthouse[http://localhost:3000/t/demo-open]"` corre `npx lighthouse --preset=perf --emulated-form-factor=mobile --output=json` e imprime performance/accessibility/best-practices; falha abaixo de 90 em performance ou acessibilidade), `docs/superpowers/notes/2026-11-04-m3-lighthouse.md` (resultados)
- Test: `test/helpers/icon_helper_test.rb` (sprite contém todos os nomes usados: o teste faz grep dos `icon("...")` em `app/views` e falha se faltar um símbolo), `test/integration/play_layout_test.rb` (sem `cdn.jsdelivr.net` no HTML das páginas `play`)

**Interfaces:**
- Consumes: todas as páginas `play` e públicas (Tasks 3–6).
- Produces: páginas `play` sem pedidos a CDN; `icon(name, class:)` com a mesma assinatura do helper actual (o organizer continua a funcionar porque o sprite cobre todos os ícones usados); nota com os scores de `/t/:slug`, `/t/:slug/standings`, `/t/:slug/pairings`, `/p/:handle` (mobile, Chrome headless) todos ≥ 90 em performance e acessibilidade.

- [ ] **Step 1: Testes** → FAIL. **Step 2: Implementar e correr o Lighthouse contra o servidor de dev com o evento `demo-open`** (se o `npx lighthouse` não correr nesta máquina, registar o motivo na nota e marcar a verificação como pendente — não bloqueia o commit). **Step 3: `bin/rails test`** → PASS. **Step 4: Commit** `perf: play pages without CDN assets, icon sprite, lighthouse task`.

---

### Task 8: Fecho do M3

- [ ] README: secção "Jogadores e público" (pt-PT, ~20 linhas: login Google/Discord e variáveis de ambiente, conta e eliminação, perfis e visibilidade, páginas públicas `/t/:slug`, `/t/:slug/pairings`, `/t/:slug/standings`, `/p/:handle`, ao vivo, notificações, Lighthouse); CLAUDE.md actualizado (OmniAuth, `identities`, Turbo Streams, sprite de ícones, rotas novas).
- [ ] `bin/rubocop && bin/brakeman --no-pager -q && bin/rails test && bin/rails test:system && bin/rails "grindin:simulate[500]"` verdes.
- [ ] Teste em iOS e Android reais: **manual, fica para o utilizador** (lista de verificação na nota do Lighthouse: entrar com Google, ver a mesa, reportar, ver as standings, abrir o perfil).
- [ ] Commit `docs: players and public section; M3 closed`.

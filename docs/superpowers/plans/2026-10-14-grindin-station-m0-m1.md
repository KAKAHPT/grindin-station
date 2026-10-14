# Grindin Station — Plano de implementação M0 (base) + M1 (motor)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ter o repositório Grindin Station a correr localmente a partir do fork `KAKAHPT/canivete`, em português, com o motor de torneio (pontos por evento, cortes 4/10/13/16/40, assentos justos, desempates fixos) coberto por testes, uma simulação de justiça no CI e um replay do MidSeason 2026.

**Architecture:** Rails 8.1 herdado do Canivete. O motor vive em `app/services/tournaments/` (serviços puros, testáveis sem UI) e nos modelos `Tournament`, `EventParticipant`, `Pod`. As configurações por evento são colunas de `events`. Nada de UI nova além do formulário do organizador e da página de standings.

**Tech Stack:** Ruby 4.0.6, Rails 8.1, PostgreSQL 17 + PostGIS, Minitest, mise, Homebrew.

**Spec:** `docs/superpowers/specs/2026-10-14-grindin-station-design.md` (secções 3, 4, 5.1–5.4, 9, 10 M0–M1).

## Global Constraints

- Base de código: clone do fork `KAKAHPT/canivete`; nenhum remoto para `fbatista/canivete`.
- Ruby `4.0.6`, Node `25.9.0` (ficheiros `.ruby-version`, `.node-version`, `mise.toml` já no repo).
- Pontos predefinidos: vitória 7, empate 1, derrota 0, bye 7; editáveis até o estado `swiss`; bloqueados depois.
- Desempates fixos, por esta ordem: pontos de match; win rate dos adversários (pontos/máximo, mínimo 1/7, só adversários reais do Swiss, sem byes nem fantasmas); adversários batidos; adversários únicos; sorteio com semente do evento.
- Pesos dos assentos: `{1 => 3, 2 => 1, 3 => 1, 4 => 2, 5 => 2}`. Assento 1 vai sempre a quem menos vezes lá esteve na mesa.
- O histórico de assentos nunca altera a composição dos pods.
- Cortes: Top 4 `[{byes:0,pods:1}]`; Top 10 `[{byes:2,pods:2},{byes:0,pods:1}]`; Top 13 `[{byes:1,pods:3},{byes:0,pods:1}]`; Top 16 `[{byes:0,pods:4},{byes:0,pods:1}]`; Top 40 `[{byes:8,pods:8},{byes:0,pods:4},{byes:0,pods:1}]`.
- Tabela de sugestões (jogadores → rondas, corte): 4–7 → 3, Top 4 (4–5 jogadores: sem corte); 8–23 → 4, Top 4; 24–31 → 4, Top 10; 32–39 → 4, Top 13; 40–63 → 5, Top 16; 64–127 → 6, Top 16; 128–255 → 7, Top 40.
- Locale predefinido `en`, `pt` (pt-PT) disponível como segunda opção (alterado a pedido do utilizador em 2026-10-14). Estilo Ruby: rubocop-rails-omakase, `# frozen_string_literal: true`, aspas duplas.
- Commits pequenos, mensagens em inglês no estilo do Canivete (`feat:`, `test:`, `chore:`).
- Desvio consciente da spec §4: as colunas de cache `event_participants.seat_counts` e `tiebreak_cache` **não** se criam em M1; `seat_counts` e os desempates calculam-se por query. A cache só entra se o M3 (páginas públicas) a mostrar necessária.

## Review Focus

1. Pod de 5 no Swiss (quando o organizador escolhe "5 pod"): o `SeatAssigner` tem de aceitar 5 jogadores e 120 ordens sem explodir nem ignorar o assento 5 — coberto em Task 9.
2. Jogador que fez drop a meio: o seu histórico de assentos não pode contaminar os outros nem rebentar o cálculo de `opponents_beaten` — coberto em Task 10.
3. Alterar `points_win` depois de rondas existirem: tem de ser recusado com erro de validação, não re-pontuar silenciosamente — coberto em Task 7.
4. Corte escolhido maior do que o nº de jogadores (Top 16 com 12 jogadores): validação no evento, não um crash no job — coberto em Task 8.
5. Dois jogadores exatamente empatados em todos os desempates: a ordem tem de ser a mesma em cada recálculo (semente), nunca aleatória entre pedidos — coberto em Task 10.

---

### Task 1: Ferramentas locais (Ruby 4, Postgres 17 + PostGIS)

**Files:**
- Nenhum ficheiro do repositório. Só instalação na máquina.

**Interfaces:**
- Produces: `mise` com `ruby 4.0.6` e `node 25.9.0`; serviço `postgresql@17` com extensão `postgis`; role `postgres` superuser com password `postgres`.

- [ ] **Step 1: Instalar mise e Postgres**

```bash
brew install mise postgresql@17 postgis
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
brew services start postgresql@17
```

- [ ] **Step 2: Criar o role usado pelo `.env`**

```bash
/opt/homebrew/opt/postgresql@17/bin/psql postgres -c "CREATE ROLE postgres SUPERUSER LOGIN PASSWORD 'postgres';"
```
Se a mensagem for "role already exists", está feito.

- [ ] **Step 3: Verificar**

Run: `/opt/homebrew/opt/postgresql@17/bin/psql -h 127.0.0.1 -U postgres -c "select postgis_full_version();" postgres`
Expected: uma linha com `POSTGIS="3.`. (Se a extensão não existir ainda: `CREATE EXTENSION postgis;` numa base de dados de teste; o `db:prepare` da Task 3 cria-a por migração.)

---

### Task 2: Repositório Grindin Station a partir do fork

**Files:**
- Create: `grindin-station/` (clone) em `/Users/kakahpt/Desktop/GRINDIN STATION/grindin-station`
- Create: `grindin-station/LICENSE`, `grindin-station/CREDITS.md`
- Create: `grindin-station/docs/superpowers/specs/…`, `grindin-station/docs/superpowers/plans/…` (cópia desta pasta `docs/`)

**Interfaces:**
- Produces: repositório GitHub privado `KAKAHPT/grindin-station`, ramo `main`, único remoto `origin`.

- [ ] **Step 1: Clonar o fork e cortar o remoto**

```bash
cd "/Users/kakahpt/Desktop/GRINDIN STATION"
git clone https://github.com/KAKAHPT/canivete grindin-station
cd grindin-station
git remote remove origin
```

- [ ] **Step 2: Copiar a documentação e escrever LICENSE e CREDITS**

```bash
cp -R "../docs" ./docs
```
`LICENSE`: texto MIT padrão com a linha `Copyright (c) 2023-2026 Fábio Batista (Canivete) and cEDH PT (Grindin Station)`.
`CREDITS.md`: três frases — origem no Canivete de Fábio Batista (fbatista/canivete), fork `KAKAHPT/canivete`, data 2026-10-14.

- [ ] **Step 3: Commit e criar o repositório remoto**

```bash
git add LICENSE CREDITS.md docs
git commit -m "chore: start Grindin Station from the Canivete fork; add license, credits and design docs"
gh repo create KAKAHPT/grindin-station --private --source=. --remote=origin --push
```

- [ ] **Step 4: Verificar**

Run: `git remote -v && gh repo view KAKAHPT/grindin-station --json isPrivate,defaultBranchRef -q '.isPrivate,.defaultBranchRef.name'`
Expected: só `origin` (duas linhas) e depois `true` e `main`.

---

### Task 3: Ambiente a funcionar e testes do Canivete verdes

**Files:**
- Create: `grindin-station/.env` (não versionado; já está no `.gitignore`)
- Modify (só se o `bundle install` falhar em Ruby 4 / macOS): `Gemfile.lock`

**Interfaces:**
- Produces: `bin/rails test` verde; `bin/dev` a servir em `http://localhost:3000`.

- [ ] **Step 1: Ruby e Node do projeto**

```bash
cd grindin-station && mise install && mise exec -- ruby -v
```
Expected: `ruby 4.0.6`.

- [ ] **Step 2: `.env` com ligação TCP**

```bash
printf 'DB_HOST=127.0.0.1\n' > .env
```

- [ ] **Step 3: Dependências e base de dados**

```bash
mise exec -- bin/setup --skip-server
```
Expected: termina sem erro; cria `canivete_development` e `canivete_test`. Se uma gem nativa falhar (pg, herb), corrigir com `bundle config build.pg --with-pg-config=/opt/homebrew/opt/postgresql@17/bin/pg_config` e repetir; registar a correção no `README.md` (secção "Setup no macOS").

- [ ] **Step 4: Testes de base**

Run: `mise exec -- bin/rails test`
Expected: `0 failures, 0 errors`. Se houver falhas herdadas, anotá-las uma a uma num ficheiro `docs/superpowers/notes/2026-10-14-baseline-failures.md` e corrigi-las só se forem triviais (fixture/data); caso contrário marcar `skip` com a razão. O objetivo é um baseline verde e honesto.

- [ ] **Step 5: Commit**

```bash
git add README.md docs Gemfile.lock && git commit -m "chore: document macOS setup; green baseline"
```

---

### Task 4: Rename Canivete → Grindin Station

**Files:**
- Modify: `config/application.rb` (módulo `Canivete` → `GrindinStation`), `config/database.yml` (`canivete_*` → `grindin_station_*`), `config/deploy.yml` (`service: grindin-station`, `image: kakahpt/grindin-station`), `config/cable.yml`, `config/puma.rb` (se mencionar o nome), `package.json` (`"name": "grindin-station"`), `app/views/layouts/application.html.erb` (título e nome na barra), `README.md`, `docker-compose.yml` (nomes dos contentores), `.kamal/secrets`, `Dockerfile` (só se nomear a app).
- Test: `test/system/branding_test.rb` (novo)

**Interfaces:**
- Produces: `GrindinStation::Application`; `I18n` chave `app.name` = "Grindin Station".

- [ ] **Step 1: Teste**

```ruby
# test/system/branding_test.rb
require "application_system_test_case"

class BrandingTest < ApplicationSystemTestCase
  test "home page is branded Grindin Station" do
    visit root_path
    assert_title(/Grindin Station/)
    assert_no_text "Canivete"
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/system/branding_test.rb`
Expected: FAIL no `assert_title`.

- [ ] **Step 3: Renomear**

`grep -rn -i canivete --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=docs --exclude=CREDITS.md --exclude=LICENSE .` e substituir todas as ocorrências listadas nos ficheiros acima. Título e nome visível vêm de `t("app.name")` em `config/locales/en.yml` (`app: name: "Grindin Station"`). Depois `mise exec -- bin/rails db:drop db:prepare` para recriar as bases com o novo nome.

- [ ] **Step 4: Testes**

Run: `mise exec -- bin/rails test && mise exec -- bin/rails test:system test/system/branding_test.rb`
Expected: tudo PASS; `grep -rn -i canivete` só devolve `CREDITS.md`, `LICENSE`, `docs/`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: rename application to Grindin Station"
```

---

### Task 5: Português de Portugal como língua predefinida

**Files:**
- Create: `config/locales/pt.yml`
- Modify: `config/application.rb` (`config.i18n.default_locale = :pt`, `config.i18n.available_locales = %i[pt en]`), `app/controllers/application_controller.rb` (`around_action :switch_locale`, locale de `params[:locale]` → `current_user&.locale` → predefinido), `app/views/layouts/application.html.erb` (`<html lang="<%= I18n.locale %>">`)
- Test: `test/controllers/locale_test.rb`

**Interfaces:**
- Produces: `ApplicationController#switch_locale`; todas as chaves de `en.yml` existem em `pt.yml`.

- [ ] **Step 1: Teste**

```ruby
# test/controllers/locale_test.rb
require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  test "default locale is pt and every en key is translated" do
    assert_equal :pt, I18n.default_locale
    en = I18n.backend.send(:translations)[:en]
    pt = I18n.backend.send(:translations)[:pt]
    missing = flatten_keys(en) - flatten_keys(pt)
    assert_empty missing, "missing pt keys: #{missing.join(', ')}"
  end

  test "html lang follows the locale" do
    get root_path
    assert_select "html[lang=pt]"
    get root_path(locale: "en")
    assert_select "html[lang=en]"
  end

  private

  def flatten_keys(hash, prefix = nil)
    hash.flat_map { |k, v| key = [prefix, k].compact.join("."); v.is_a?(Hash) ? flatten_keys(v, key) : [key] }
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/controllers/locale_test.rb`
Expected: FAIL (`default_locale` é `:en`).

- [ ] **Step 3: Implementar**

`pt.yml` traduz todas as chaves de `en.yml` para pt-PT (tratamento por "tu", termos de torneio: ronda, pod, assento, corte, standings mantém-se "classificação"). Os textos fixos nas views que ainda não passam por `t()` ficam para o plano M2; aqui só as chaves existentes.

- [ ] **Step 4: Testes**

Run: `mise exec -- bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config app test && git commit -m "feat: pt-PT as default locale with en fallback"
```

---

### Task 6: Congelar o comportamento do emparelhamento Swiss

**Files:**
- Create: `test/jobs/tournaments/create_pods_job_test.rb`, `test/support/tournament_builder.rb`
- Modify: `test/test_helper.rb` (`require_relative "support/tournament_builder"`)

**Interfaces:**
- Produces: `TournamentBuilder.build(players:, organizer:, state: :swiss) -> Tournament` (cria N users/players/participants em memória de teste, sem fixtures) e `TournamentBuilder.play_round!(tournament, winners: {pod_number => participant_index | :draw})` que cria `Win`/`Loss`/`Draw` por pod e marca `finished_at`. Usado por todas as tasks seguintes.

- [ ] **Step 1: Escrever o builder e os testes**

```ruby
# test/jobs/tournaments/create_pods_job_test.rb
require "test_helper"

module Tournaments
  class CreatePodsJobTest < ActiveJob::TestCase
    test "17 players: two pods of 4 and three pods of 3, lowest ranked in the small pods" do
      t = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1)   # after_create builds the pods
      assert_equal [4, 4, 3, 3, 3], round.pods.order(:number).map(&:size)
      assert_equal 17, round.seatings.count
      assert_equal 17, round.seatings.map(&:event_participant_id).uniq.size
    end

    test "round 2 standard: the four highest ranked players share pod 1" do
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      r1 = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      top4 = t.event_participants.sort_by { |p| -p.rank_score }.first(4).map(&:id).sort
      assert_equal top4, r2.pods.find_by(number: 1).event_participants.map(&:id).sort
    end

    test "players never meet twice while another pairing is possible" do
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      r2.pods.each do |pod|
        pod.event_participants.combination(2).each do |a, b|
          assert_not a.played_against?(b), "#{a.name} and #{b.name} met in round 1"
        end
      end
    end
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/jobs/tournaments/create_pods_job_test.rb`
Expected: FAIL por `TournamentBuilder` não existir.

- [ ] **Step 3: Implementar `test/support/tournament_builder.rb`**

`build` cria `User` (nome "Jogador N", e-mail `jogador-N@example.com`), o `Player` vem do callback, `EventParticipant.create!(accepted_terms: true)` e o `Tournament` com `state: :swiss` sem disparar jobs (usar `update_column(:state, …)`). `play_round!` percorre `round.pods.order(:number)`, cria `Win` para o índice indicado e `Loss` para os outros, ou `Draw` para todos, e faz `round.update!(finished_at: Time.current)` com `advance_tournament!` desligado (`Round.skip_callback` não; preferir `round.update_columns(finished_at: …)`).

- [ ] **Step 4: Correr**

Run: `mise exec -- bin/rails test test/jobs/tournaments/create_pods_job_test.rb`
Expected: PASS nos três. Se o terceiro falhar porque o `SwissMatcher` real repete adversários com 16 jogadores em empate total, isso é comportamento existente: registar em `docs/superpowers/notes/` e trocar o cenário para um onde a não repetição é possível (ex.: 20 jogadores), mantendo o teste.

- [ ] **Step 5: Commit**

```bash
git add test && git commit -m "test: freeze Swiss pod generation behaviour"
```

---

### Task 7: Pontos por evento (editáveis até o Swiss começar)

**Files:**
- Create: `db/migrate/<ts>_add_points_to_events.rb`
- Modify: `app/models/event.rb`, `app/models/event_participant.rb`, `app/models/ghost.rb`, `app/models/tournament.rb` (constantes passam a defaults), `app/controllers/organizer/tournaments_controller.rb` (`tournament_params`), `app/views/organizer/tournaments/_form.html.erb`, `config/locales/en.yml`, `config/locales/pt.yml`
- Test: `test/models/event_points_test.rb`

**Interfaces:**
- Produces: colunas `events.points_win` (int, default 7), `points_draw` (1), `points_loss` (0), `points_bye` (7); `Event#points_locked?` → true quando `state` não é draft/registration_open/registration_closed; validação `points cannot change after the tournament started`; `EventParticipant#match_points` lê `event.points_*`.

- [ ] **Step 1: Teste**

```ruby
# test/models/event_points_test.rb
require "test_helper"

class EventPointsTest < ActiveSupport::TestCase
  test "defaults are 7/1/0/7" do
    t = Tournament.new
    assert_equal [7, 1, 0, 7], [t.points_win, t.points_draw, t.points_loss, t.points_bye]
  end

  test "match points use the event's values" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.update_columns(points_win: 5, points_draw: 2)
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0 })
    winner = t.rounds.first.pods.first.event_participants.first
    assert_equal 5, winner.reload.match_points
  end

  test "points are locked once the swiss starts" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.points_win = 9
    assert_not t.valid?
    assert_includes t.errors[:points_win], I18n.t("activerecord.errors.models.event.attributes.points_win.locked")
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/models/event_points_test.rb`
Expected: FAIL (`points_win` desconhecido).

- [ ] **Step 3: Implementar**

Migração com os quatro inteiros `null: false` e defaults. Em `Event`: `validate :points_locked_after_start, on: :update` que adiciona erro `:locked` a cada campo alterado quando `points_locked?`. `EventParticipant#match_points = draws × event.points_draw + wins × event.points_win`; byes (`Advance` em `SwissRound`) × `event.points_bye` — adicionar `number_of_byes` (Advance cujo round é SwissRound) e deixar `number_of_advancements` só para rondas de eliminação. `match_win_percentage` usa `event.points_win` como máximo. `Ghost#match_win_percentage` → `event.points_draw.to_f / event.points_win`. Formulário: quatro `number_field_with_label`, desativados quando `points_locked?`, com ajuda `t("organizer.points_help")`.

- [ ] **Step 4: Testes**

Run: `mise exec -- bin/rails test`
Expected: PASS (incluindo `tournament_test.rb`: atualizar o teste das constantes para os novos defaults se necessário).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: per-event points for win, draw, loss and bye, locked once the swiss starts"
```

---

### Task 8: Rondas e corte configuráveis, cortes Top 4/10/13/16/40

**Files:**
- Create: `app/services/tournaments/top_cut.rb`, `app/services/tournaments/structure.rb`, `db/migrate/<ts>_add_structure_to_events.rb`
- Modify: `app/models/tournament.rb` (`rounds_info`, `number_of_swiss_rounds`, `number_of_single_elimination_rounds`, validação), `app/models/swiss_round.rb` e `app/models/single_elimination_round.rb` (`duration` lê o evento), `app/jobs/tournaments/create_single_elimination_pods_job.rb` (usa `TopCut`), `app/controllers/organizer/tournaments_controller.rb`, `app/views/organizer/tournaments/_form.html.erb`, locales
- Test: `test/services/tournaments/top_cut_test.rb`, `test/services/tournaments/structure_test.rb`, `test/jobs/tournaments/create_single_elimination_pods_job_test.rb`

**Interfaces:**
- Produces: colunas `events.swiss_rounds_count` (int, nullable), `top_cut_size` (int, nullable; 0 = sem corte), `round_minutes` (int, default 80), `top_cut_round_minutes` (int, default 150).
- `Tournaments::TopCut.for(size) -> TopCut` com `#players`, `#stages -> [{byes:, pods:}]`, `#rounds` (= stages.size), `#valid_for?(player_count)`; `TopCut::SIZES = [4, 10, 13, 16, 40]`.
- `Tournaments::Structure.suggested(player_count) -> {swiss_rounds:, top_cut_size:}` com a tabela dos Global Constraints.
- `Tournament#rounds_info` mantém a forma `{rounds: [{swiss_round: :standard|:spread|:forced}, …], top: {players:, pods: [m, …]}}` que o resto do Canivete já lê, agora derivada de `swiss_rounds_count`/`top_cut_size` (ou da sugestão quando nil). Estratégias: ronda 1 standard, ronda 2 spread (se ≥ 3 rondas), última forced (se ≥ 4 rondas), restantes standard.

- [ ] **Step 1: Testes**

```ruby
# test/services/tournaments/top_cut_test.rb
require "test_helper"

class Tournaments::TopCutTest < ActiveSupport::TestCase
  test "stages per size" do
    assert_equal [{ byes: 0, pods: 1 }], Tournaments::TopCut.for(4).stages
    assert_equal [{ byes: 2, pods: 2 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(10).stages
    assert_equal [{ byes: 1, pods: 3 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(13).stages
    assert_equal [{ byes: 0, pods: 4 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(16).stages
    assert_equal [{ byes: 8, pods: 8 }, { byes: 0, pods: 4 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(40).stages
  end

  test "unknown size raises and validity needs enough players" do
    assert_raises(ArgumentError) { Tournaments::TopCut.for(8) }
    assert Tournaments::TopCut.for(16).valid_for?(16)
    assert_not Tournaments::TopCut.for(16).valid_for?(12)
  end
end
```

```ruby
# test/services/tournaments/structure_test.rb
require "test_helper"

class Tournaments::StructureTest < ActiveSupport::TestCase
  test "suggestions follow the spec table" do
    expected = { 4 => [3, 0], 7 => [3, 4], 8 => [4, 4], 23 => [4, 4], 24 => [4, 10], 31 => [4, 10],
                 32 => [4, 13], 39 => [4, 13], 40 => [5, 16], 63 => [5, 16], 64 => [6, 16], 127 => [6, 16], 128 => [7, 40] }
    expected.each do |n, (rounds, cut)|
      s = Tournaments::Structure.suggested(n)
      assert_equal [rounds, cut], [s[:swiss_rounds], s[:top_cut_size]], "for #{n} players"
    end
  end

  test "tournament rejects a cut bigger than the field" do
    t = TournamentBuilder.build(players: 12, organizer: event_organizers(:standard_organizer), state: :registration_closed)
    t.top_cut_size = 16
    assert_not t.valid?
    assert_includes t.errors[:top_cut_size], I18n.t("activerecord.errors.models.event.attributes.top_cut_size.too_big")
  end

  test "rounds_info strategies: 1 standard, 2 spread, last forced" do
    t = TournamentBuilder.build(players: 40, organizer: event_organizers(:standard_organizer))
    assert_equal %i[standard spread standard standard forced], t.rounds_info[:rounds].map { |r| r[:swiss_round] }
    assert_equal({ players: 16, pods: [4, 1] }, t.rounds_info[:top])
  end
end
```

```ruby
# test/jobs/tournaments/create_single_elimination_pods_job_test.rb
require "test_helper"

module Tournaments
  class CreateSingleEliminationPodsJobTest < ActiveJob::TestCase
    test "top 13: seed 1 advances, seeds 2-13 play three pods, the rest are eliminated" do
      t = TournamentBuilder.build(players: 32, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 13)
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: (1..8).to_h { |n| [n, 0] })
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      seeds = t.event_participants.sort_by { |p| -p.rank_score }
      assert_equal 3, cut.pods.count
      assert_equal [seeds.first.id], cut.results.where(type: "Advance").pluck(:event_participant_id)
      assert_equal 19, cut.results.where(type: "Eliminated").count
      assert_equal seeds[1..12].map(&:id).sort, cut.seatings.map(&:event_participant_id).sort
    end

    test "top 40 has three elimination rounds" do
      t = TournamentBuilder.build(players: 130, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 40)
      assert_equal 3, t.number_of_single_elimination_rounds
      assert_equal "Quarter-Finals", t.single_elimination_round_name(2)
    end
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/services/tournaments test/jobs/tournaments/create_single_elimination_pods_job_test.rb`
Expected: FAIL (`Tournaments::TopCut` desconhecido).

- [ ] **Step 3: Implementar**

`TopCut` é um `Data`/`Struct` imutável com uma constante `STAGES = { 4 => […], 10 => […], … }`. `Structure.suggested` é um `case` sobre intervalos. `Tournament#rounds_info` calcula `rounds` pelo nº e `top` como `{players: cut.players, pods: cut.stages.map { _1[:pods] }}` (ou `nil` com `top_cut_size == 0`). Em `CreateSingleEliminationPodsJob`, `players_making_the_cut` continua a ler `rounds_info[:top][:players]` e `number_of_pods` o índice da etapa — a forma mantém-se, só a origem muda. Validação em `Tournament`: `top_cut_size` ∈ `[0] + TopCut::SIZES` e `TopCut.for(size).valid_for?(event_participants.size)` quando `state` passa a `swiss`. `SwissRound#duration = event.round_minutes.minutes`; `SingleEliminationRound#duration = event.top_cut_round_minutes.minutes` exceto na última (`nil`). `single_elimination_round_name` cobre 3 etapas (`%w[Finals Semi-Finals Quarter-Finals]` já cobre). Formulário: campos `swiss_rounds_count` e `top_cut_size` (select com `Sem corte` + tamanhos) com a sugestão visível `t("organizer.structure_suggestion", rounds:, cut:)`, `round_minutes`, `top_cut_round_minutes`; bloqueados quando `points_locked?`.

- [ ] **Step 4: Testes**

Run: `mise exec -- bin/rails test`
Expected: PASS. Os testes antigos de `tournament_test.rb` sobre `PLAYERS_ROUNDS_THRESHOLDS` são substituídos pelos novos (apagar os que testam a tabela antiga).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: configurable swiss rounds and top cut (4/10/13/16/40) with suggested structure"
```

---

### Task 9: Assentos justos — `Tournaments::SeatAssigner`

**Files:**
- Create: `app/services/tournaments/seat_assigner.rb`, `db/migrate/<ts>_add_seat_audit_to_seatings_and_seed_to_events.rb`
- Modify: `app/models/pod.rb` (`sit_participants!`, remover `weighted_seatings`), `app/models/event_participant.rb` (`seat_counts`), `app/models/tournament.rb` (semente ao entrar em `swiss`)
- Test: `test/services/tournaments/seat_assigner_test.rb`, `test/models/pod_seating_test.rb`

**Interfaces:**
- Produces: colunas `seatings.assigned_by` (string, default "fair"), `seatings.cost` (int, nullable), `events.seed` (int, nullable).
- `EventParticipant#seat_counts -> Hash{Integer => Integer}` com as posições 1..5 (0 quando nunca), contadas só em `SwissRound` com `finished_at` ou `published`, sem byes.
- `Tournaments::SeatAssigner.new(participants:, seat_counts:, rng:)`: `participants` array (3–5), `seat_counts` Hash participant → Hash posição → vezes, `rng` um `Random`. `#order -> Array` (posição 1 primeiro) e `#cost -> Integer` da ordem escolhida. `WEIGHTS = { 1 => 3, 2 => 1, 3 => 1, 4 => 2, 5 => 2 }`.
- `Pod#sit_participants!` grava `assigned_by: "fair"` + `cost` no Swiss e `assigned_by: "ranked"` na eliminação.

- [ ] **Step 1: Testes**

```ruby
# test/services/tournaments/seat_assigner_test.rb
require "test_helper"

class Tournaments::SeatAssignerTest < ActiveSupport::TestCase
  A, B, C, D, E = %w[a b c d e]

  def counts(h) = h.transform_values { |arr| (1..5).zip(arr + [0] * (5 - arr.size)).to_h }

  test "seat 1 goes to the player who has had it least" do
    sc = counts(A => [1, 0, 0, 0], B => [0, 1, 0, 0], C => [1, 0, 1, 0], D => [2, 0, 0, 0])
    order = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(1)).order
    assert_equal B, order.first
  end

  test "among seat-1 candidates the cheapest full order wins" do
    sc = counts(A => [0, 2, 0, 0], B => [0, 0, 2, 0], C => [1, 0, 0, 2], D => [1, 1, 1, 0])
    assigner = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(1))
    assert_includes [A, B], assigner.order.first
    assert_equal D, assigner.order.last, "D is the only one who never sat 4th"
    assert_equal assigner.cost, assigner.order.each_with_index.sum { |p, i| Tournaments::SeatAssigner::WEIGHTS[i + 1] * sc[p][i + 1]**2 }
  end

  test "ties are decided by the rng, reproducibly" do
    sc = counts(A => [], B => [], C => [], D => [])
    o1 = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(42)).order
    o2 = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(42)).order
    o3 = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(7)).order
    assert_equal o1, o2
    assert_not_equal o1, o3
  end

  test "handles pods of 3 and 5" do
    sc = counts(A => [], B => [], C => [], D => [], E => [0, 0, 0, 0, 3])
    assert_equal 3, Tournaments::SeatAssigner.new(participants: [A, B, C], seat_counts: sc, rng: Random.new(1)).order.size
    five = Tournaments::SeatAssigner.new(participants: [A, B, C, D, E], seat_counts: sc, rng: Random.new(1)).order
    assert_equal 5, five.size
    assert_not_equal E, five.last
  end
end
```

```ruby
# test/models/pod_seating_test.rb
require "test_helper"

class PodSeatingTest < ActiveSupport::TestCase
  test "swiss seatings are fair and audited; elimination seatings are ranked" do
    t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2, top_cut_size: 4, seed: 123)
    r1 = t.rounds.create!(type: SwissRound, number: 1)
    assert r1.seatings.all? { |s| s.assigned_by == "fair" && s.cost == 0 }
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    r2.pods.each do |pod|
      first = pod.seatings.order(:order).first.event_participant
      assert_equal 0, first.seat_counts[1], "round 2 seat 1 must go to someone who never had it"
    end
    TournamentBuilder.play_round!(t, winners: { 1 => 1, 2 => 1 })
    cut = t.rounds.create!(type: SingleEliminationRound, number: 3)
    seeds = t.event_participants.sort_by { |p| -p.rank_score }.first(4)
    assert_equal seeds.map(&:id), cut.pods.first.seatings.order(:order).map(&:event_participant_id)
    assert cut.seatings.all? { |s| s.assigned_by == "ranked" }
  end

  test "seat_counts ignores byes and unfinished rounds" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    p = t.event_participants.first
    assert_equal({ 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0 }, p.seat_counts)
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/services/tournaments/seat_assigner_test.rb test/models/pod_seating_test.rb`
Expected: FAIL (`SeatAssigner` desconhecido).

- [ ] **Step 3: Implementar**

`SeatAssigner#order`: `participants.permutation.to_a`, filtra as ordens cujo primeiro elemento tem o mínimo `seat_counts[p][1]`, calcula `cost` de cada, fica com as de custo mínimo, escolhe uma com `rng.rand(n)`. `Pod#sit_participants!`: na `SingleEliminationRound` mantém `ranked_seatings` + `assigned_by: "ranked"`; no Swiss constrói `seat_counts` dos candidatos, `rng = Random.new([event.seed.to_i, round.number, number].hash)`, grava `order`, `cost` e `assigned_by: "fair"`. `EventParticipant#seat_counts`: um `group(:order).count` sobre `seatings` dos `SwissRound` finished/published, preenchido para 1..5. `Tournament`: ao transitar para `swiss`, `self.seed ||= SecureRandom.random_number(2**31)` (em `perform_state_based_actions` antes do job). Apagar `weighted_seatings` e `times_going_at`.

- [ ] **Step 4: Testes**

Run: `mise exec -- bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: fair seat assignment in swiss pods with audit trail; ranked seats in the top cut"
```

---

### Task 10: Desempates fixos e ordem determinística

**Files:**
- Modify: `app/models/event_participant.rb` (`rank_score`, novos métodos, remover `corrected_opponents` do OWR), `app/models/ghost.rb` (remover métodos que deixam de existir), `app/views/tournaments/_tournament_details.html.erb` ou a partial de standings existente (colunas + assentos), `app/views/tournaments/_standings_help.html.erb` (nova), locales
- Test: `test/models/tiebreakers_test.rb`

**Interfaces:**
- Produces em `EventParticipant`: `#match_points`, `#opponents_win_rate -> Float` (média de `opp.match_points / (opp.swiss_games × event.points_win)`, cada termo com mínimo `event.points_draw.to_f / event.points_win`, só adversários de `SwissRound`, sem byes/fantasmas; 0.0 sem adversários), `#opponents_beaten -> Integer` (adversários distintos nas mesas onde teve `Win`), `#unique_opponents -> Integer`, `#tiebreak_salt -> Integer` (0..9999, `Digest::MD5.hexdigest("#{event.seed}-#{id}").to_i(16) % 10_000`), `#swiss_games -> Integer` (resultados em SwissRound que não são Advance).
- `#rank_score` = `advancements × 10**18 + match_points × 10**13 + (opponents_win_rate.round(4) × 10_000).to_i × 10**8 + opponents_beaten × 10**6 + unique_opponents × 10**4 + tiebreak_salt`. Ligas mantêm `league_score`.
- `#standing_columns -> Hash` com as cinco componentes legíveis, para a view.

- [ ] **Step 1: Teste**

```ruby
# test/models/tiebreakers_test.rb
require "test_helper"

class TiebreakersTest < ActiveSupport::TestCase
  setup do
    @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @t.update_columns(seed: 99, swiss_rounds_count: 2, top_cut_size: 0)
    @t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => :draw })
    @r1 = @t.rounds.first
    @winner = @r1.pods.find_by(number: 1).seatings.order(:order).first.event_participant
    @drawer = @r1.pods.find_by(number: 2).event_participants.first
  end

  test "components after one round" do
    assert_equal 7, @winner.match_points
    assert_equal 3, @winner.opponents_beaten
    assert_equal 3, @winner.unique_opponents
    assert_in_delta 1.0 / 7, @winner.opponents_win_rate, 0.0001   # three losers, each floored at 1/7
    assert_equal 1, @drawer.match_points
    assert_in_delta 1.0 / 7, @drawer.opponents_win_rate, 0.0001   # three drawers at 1/7 exactly
  end

  test "rank_score orders by points, then opponents win rate, then beaten, then unique, then salt" do
    others = @r1.pods.find_by(number: 2).event_participants.sort_by(&:rank_score).reverse
    assert_equal others.map(&:tiebreak_salt).sort.reverse, others.map(&:tiebreak_salt), "equal drawers fall back to the salt"
    assert_operator @winner.rank_score, :>, others.first.rank_score
  end

  test "a dropped player keeps counting as an opponent and the salt is stable" do
    loser = @r1.pods.find_by(number: 1).seatings.order(:order).last.event_participant
    loser.update_columns(dropped: true)
    assert_equal 3, @winner.reload.opponents_beaten
    assert_equal @winner.tiebreak_salt, EventParticipant.find(@winner.id).tiebreak_salt
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/models/tiebreakers_test.rb`
Expected: FAIL (`opponents_beaten` desconhecido).

- [ ] **Step 3: Implementar**

Os métodos acima em `EventParticipant`; `opponents` já exclui rondas de eliminação. `opponents_beaten`: para cada `Win` em SwissRound, os outros `event_participants` do pod dessa ronda. Apagar `opponents_average_match_points`, `opponents_average_match_win_percentage`, `corrected_opponents`, `number_of_ghost_opponents` e os `*_COEFF` antigos; `Ghost` fica só com o que ainda é chamado (ou é apagado se nada o usar — verificar com `grep -rn Ghost app`). Na view de standings: colunas Pts · OWR% · Bat · Únicos · Assentos (`seat_counts` como "2·1·1·1") e a partial `_standings_help` com um parágrafo por desempate (`t("standings.help.*")`, pt e en).

- [ ] **Step 4: Testes**

Run: `mise exec -- bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: fixed cEDH PT tiebreakers with seeded deterministic ordering; standings explain them"
```

---

### Task 11: Simulação de justiça no CI — `grindin:simulate`

**Files:**
- Create: `app/services/tournaments/seat_simulator.rb`, `lib/tasks/grindin.rake`
- Modify: `.github/workflows/ci.yml` (job `simulate` depois de `test`)
- Test: `test/services/tournaments/seat_simulator_test.rb`

**Interfaces:**
- Produces: `Tournaments::SeatSimulator.new(players:, rounds:, rng:)` com `#run -> Report`; `Report` tem `never_first_rate` (fração de jogadores sem assento 1), `max_spread_le1_rate` (fração de jogadores cuja diferença máx–mín de contagens ≤ 1), `worst` (Hash jogador → contagens). Sem base de dados: pods aleatórios de 4 (sobras em pods de 3) a partir de pontos simulados (30 % empates), assentos por `SeatAssigner`.
- Task `grindin:simulate[n]` corre `n` torneios com jogadores ∈ 16..140 e rondas ∈ 4..7, imprime as médias e **falha (exit 1)** se `never_first_rate > 0.01` para rondas ≥ 4 ou `max_spread_le1_rate < 0.99`.

- [ ] **Step 1: Teste**

```ruby
# test/services/tournaments/seat_simulator_test.rb
require "test_helper"

class Tournaments::SeatSimulatorTest < ActiveSupport::TestCase
  test "a 4-round, 40-player tournament seats everyone first at least once nearly always" do
    rates = 50.times.map { |i| Tournaments::SeatSimulator.new(players: 40, rounds: 4, rng: Random.new(i)).run.never_first_rate }
    assert_operator rates.sum / rates.size, :<=, 0.01
  end

  test "spread stays within one seat for almost everyone over 5 rounds" do
    report = Tournaments::SeatSimulator.new(players: 64, rounds: 5, rng: Random.new(3)).run
    assert_operator report.max_spread_le1_rate, :>=, 0.99
  end
end
```

- [ ] **Step 2: Correr e ver falhar**

Run: `mise exec -- bin/rails test test/services/tournaments/seat_simulator_test.rb`
Expected: FAIL (`SeatSimulator` desconhecido).

- [ ] **Step 3: Implementar e calibrar**

Implementar o simulador e a task. Correr `mise exec -- bin/rails "grindin:simulate[2000]"` e ler o relatório. Se os limiares não forem atingidos pelo algoritmo ganancioso, **não baixar os limiares**: aplicar o refinamento previsto na spec §5.3 dentro do `SeatAssigner` chamado pelo simulador — antes de formar os pods de uma ronda, entre jogadores com os mesmos pontos, ordenar por `seat_counts[1]` crescente, de modo que os "devedores" de assento 1 se espalhem por pods diferentes (isto só reordena empates de pontos, logo respeita a regra "o histórico não altera a composição por força"). Se mesmo assim falhar, registar os números reais em `docs/superpowers/notes/2026-10-xx-seat-simulation.md` e parar para decidir com o Kakah.

- [ ] **Step 4: Testes e CI**

Run: `mise exec -- bin/rails test && mise exec -- bin/rails "grindin:simulate[500]"`
Expected: PASS e a task termina com `OK` e as duas taxas dentro dos limites. Adicionar ao `ci.yml` o passo `bin/rails "grindin:simulate[500]"` no job `test`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: seat fairness simulator with CI gate"
```

---

### Task 12: Replay do MidSeason 2026 contra a classificação do TopDeck

**Files:**
- Create: `test/fixtures/files/midseason-2026-rounds.json` (feed `rounds` público do cedhpt.com: `https://cedhpt.com/api/topdeck.php?feed=rounds&tid=midseason-cedh-pt-cedh-european-championship-invitational`), `test/fixtures/files/midseason-2026-standings.json` (feed `standings`), `test/support/topdeck_replay.rb`
- Test: `test/integration/midseason_replay_test.rb`

**Interfaces:**
- Produces: `TopdeckReplay.load(rounds_json:) -> Tournament` que cria participantes pelos nomes, uma `SwissRound` por ronda numérica com os pods e assentos **exatamente como no ficheiro** (sem emparelhar: `round.pods.build` + `seatings.build` diretos, `assigned_by: "manual"`), resultados Win/Loss/Draw pelo `winner`/`draw`, e marca cada ronda `finished_at`.

- [ ] **Step 1: Teste**

```ruby
# test/integration/midseason_replay_test.rb
require "test_helper"

class MidseasonReplayTest < ActiveSupport::TestCase
  test "our standings reproduce TopDeck's Top 16 and the top 4 seeds after 5 swiss rounds" do
    rounds = JSON.parse(file_fixture("midseason-2026-rounds.json").read)
    t = TopdeckReplay.load(rounds_json: rounds)
    ours = t.event_participants.sort_by { |p| -p.rank_score }.map(&:name)
    topdeck_top16 = rounds["rounds"].find { |r| r["round"] == "Top 16" }["tables"].flat_map { |tb| tb["players"].map { _1["name"] } }
    assert_equal topdeck_top16.sort, ours.first(16).sort
    seeds = rounds["rounds"].find { |r| r["round"] == "Top 16" }["tables"].flat_map { |tb| tb["players"] }.sort_by { _1["seed"] }.first(4).map { _1["name"] }
    assert_equal seeds, ours.first(4)
  end

  test "match points match TopDeck's points column for every player" do
    rounds = JSON.parse(file_fixture("midseason-2026-rounds.json").read)
    standings = JSON.parse(file_fixture("midseason-2026-standings.json").read)["standings"]
    t = TopdeckReplay.load(rounds_json: rounds)
    t.event_participants.each do |p|
      expected = standings.find { _1["name"] == p.name }["points"]
      assert_equal expected, p.match_points, p.name
    end
  end
end
```

- [ ] **Step 2: Descarregar as fixtures e correr**

```bash
curl -s 'https://cedhpt.com/api/topdeck.php?feed=rounds&tid=midseason-cedh-pt-cedh-european-championship-invitational' > test/fixtures/files/midseason-2026-rounds.json
curl -s 'https://cedhpt.com/api/topdeck.php?feed=standings&tid=midseason-cedh-pt-cedh-european-championship-invitational' > test/fixtures/files/midseason-2026-standings.json
mise exec -- bin/rails test test/integration/midseason_replay_test.rb
```
Expected: FAIL (`TopdeckReplay` desconhecido).

- [ ] **Step 3: Implementar `test/support/topdeck_replay.rb`**

Só rondas cujo `round` é uma string de dígitos (`"1"`…`"5"`; no ficheiro os números vêm como strings). Nomes duplicados não existem no ficheiro (verificar com `uniq`). Pods com `players.size` 3 ou 5 criam `Pod` com esse `size` (o MidSeason tem 7 pods de 3). Um jogador que não aparece numa ronda fez drop: marcar `dropped: true` depois da última ronda em que jogou. A ordem `rank` do ficheiro de standings é a classificação final pós-corte, não a do Swiss: nunca comparar por `rank`, só por `points` e pelo conjunto do Top 16.

- [ ] **Step 4: Correr**

Run: `mise exec -- bin/rails test test/integration/midseason_replay_test.rb`
Expected: PASS. Se o primeiro teste falhar só na ordem dos seeds 1–4 por uma diferença de definição do OWR (TopDeck pode usar outro mínimo), documentar a diferença em `docs/superpowers/notes/` com os números dos dois lados, manter a asserção do conjunto Top 16 e relaxar a dos seeds para "os mesmos 4 jogadores" — e dizer isto explicitamente no relatório final.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "test: replay MidSeason 2026 and match TopDeck's cut and points"
```

---

### Task 13: Fecho do M1

**Files:**
- Modify: `README.md` (secção "Motor do torneio": pontos, cortes, assentos, desempates, como correr a simulação e o replay), `docs/superpowers/plans/2026-10-14-grindin-station-m0-m1.md` (checkboxes)

- [ ] **Step 1: Verificação completa**

Run: `mise exec -- bin/rubocop && mise exec -- bin/brakeman --no-pager -q && mise exec -- bin/rails test && mise exec -- bin/rails "grindin:simulate[500]"`
Expected: tudo sem ofensas, 0 falhas, simulação `OK`.

- [ ] **Step 2: Push e CI**

```bash
git push origin main
gh run watch --exit-status
```
Expected: CI verde no GitHub.

- [ ] **Step 3: Commit da documentação**

```bash
git add README.md docs && git commit -m "docs: engine section and M0-M1 plan closed" && git push
```

---

### Task 14: Reencontros evitados em todas as rondas Swiss (executar logo após a Task 6)

Origem: a Task 6 descobriu que o `SwissMatcher` herdado só evita reencontros nas rondas `:forced`, o `SpreadMatcher` nunca os evita e o código de swaps está partido (ver `docs/superpowers/notes/2026-10-14-swiss-matcher-notes.md`). A spec §5.2 exige "sem repetir adversários salvo impossibilidade".

**Files:**
- Create: `app/services/tournaments/rematch_repair.rb`
- Modify: `app/services/tournaments/strategies/swiss_matcher.rb` (só `initial_match!` com `force_candidate`; apagar `handle_unmatched_players!`, `attempt_swaping!`, `sort_pod_by_rank_diff`, `incomplete_pods`, `find_swap_candidate`, `swap!`, `unmatched_players`, o parâmetro `forced:`), `app/jobs/tournaments/create_pods_job.rb` (chama o repair depois da estratégia, antes de `sit_participants!`), `app/models/pod.rb` (apagar `receive_candidate`, `can_match?`, `swap_suitable_by_rank_for?`, `swap_suitable_by_rematch_for?`, `a_swap_candidate_by_rematch_for`, `best_swap_candidate_by_rank_for`, `candidates_average_rank` e `swap_candidates!` se mais nada os usar — confirmar com `grep -rn` em `app/`), `app/models/event.rb` e `app/models/tournament.rb` (apagar `PAIR_DOWN_DEVIATION_PERCENT` se ficar sem uso), `app/models/event_participant.rb` (apagar `played_in_smaller_pod?` se ficar sem uso)
- Test: `test/services/tournaments/rematch_repair_test.rb`, `test/jobs/tournaments/create_pods_job_test.rb` (retirar o `skip` do teste "players never meet twice…" e acrescentar os dois testes abaixo)

**Interfaces:**
- Consumes: `Pod#candidates` (array em memória preenchido pelas estratégias), `EventParticipant#played_against?`, `#match_points`, `#rank_score`.
- Produces: `Tournaments::RematchRepair.new(round, max_point_gap:)` com `#repair!` → Integer (reencontros que sobraram). `max_point_gap` = 0 para `:standard` (só troca jogadores com os mesmos `match_points`), `Float::INFINITY` para `:spread` e `:forced`. Algoritmo: enquanto existir um par (a, b) no mesmo pod com `a.played_against?(b)`, procurar uma troca de um deles com um candidato c de outro pod (respeitando o gap em pontos entre o trocado e c) que **reduza estritamente** o nº total de pares repetidos na ronda; aplicar a primeira que reduzir; parar quando nenhuma troca reduz (máximo `20 × nº de pods` iterações). Determinístico dado o estado inicial.
- `CreatePodsJob` chama `RematchRepair.new(@round, max_point_gap: gap_for(strategy)).repair!` depois de `match_according_to_strategy!`.

- [ ] **Step 1: Testes**

```ruby
# test/services/tournaments/rematch_repair_test.rb
require "test_helper"

class Tournaments::RematchRepairTest < ActiveSupport::TestCase
  test "removes every rematch when a clean arrangement exists (16 players after an all-draw round)" do
    t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw })
    r2 = t.rounds.create!(type: SwissRound, number: 2)   # job runs strategy + repair
    assert_equal 0, rematch_pairs(r2)
  end

  test "standard rounds never move a player out of their points group" do
    t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    winners = t.event_participants.select { |p| p.match_points == 7 }.map(&:id).sort
    assert_equal winners, r2.pods.find_by(number: 1).event_participants.map(&:id).sort
    assert_equal 0, rematch_pairs(r2)
  end

  test "an unavoidable rematch still seats everyone and terminates (4 players, round 2)" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2) if t.has_attribute?(:swiss_rounds_count)
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    assert_equal 4, r2.seatings.count
    assert_equal 6, rematch_pairs(r2)
  end

  private

  def rematch_pairs(round)
    round.pods.sum { |pod| pod.event_participants.to_a.combination(2).count { |a, b| a.played_against?(b) } }
  end
end
```

E em `create_pods_job_test.rb`: retirar o `skip` do terceiro teste; acrescentar `test "spread round (20 players) has no rematches"` (20 jogadores, ronda 1 toda em empate, ronda 2 → `rematch_pairs == 0`).

- [ ] **Step 2: Correr e ver falhar**

Run: `bin/rails test test/services/tournaments/rematch_repair_test.rb test/jobs/tournaments/create_pods_job_test.rb`
Expected: FAIL (`RematchRepair` desconhecido; o teste 3 da Task 6 falha com reencontros).

- [ ] **Step 3: Implementar**

`RematchRepair` como descrito nas Interfaces. Nos testes com 4 jogadores a ronda 2 só existe se `rounds_info` o permitir: se `Tournament::PLAYERS_ROUNDS_THRESHOLDS` ainda der 1 ronda para 4 jogadores, criar a ronda 2 na mesma (o `CreatePodsJob` lê `rounds_info[:rounds][number - 1]`, que será `nil` → tratar `nil` como `:standard`). Apagar o código órfão listado em Files. Se a pesquisa local deixar reencontros num caso em que existe arranjo limpo (teste 1 ou o teste da Task 6 a falhar de forma reprodutível), acrescentar um segundo tipo de movimento (rotação a três entre três pods) antes de desistir — e só então reportar.

- [ ] **Step 4: Testes**

Run: `bin/rails test`
Expected: PASS, 0 skips.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: avoid rematches in every swiss round with a post-pairing repair pass; drop the broken swap code"
```

# TODO

## Tech

- [ ] Remove all possible N+1 queries
- [ ] Proper hosting and domain etc.
- [ ] Improve mobile experience

## Product

- [ ] Monetization / sponsorship to cover the tech costs.
- [ ] Extra Time management per pod.
- [ ] End of Round floor planner displaying extra time.
- [ ] Judge account
- [ ] User profiles
  - For players, check track records.
  - For TOs, see tournaments organized by a TO.
  - For judges, see tournaments they helped run.
- [ ] Manage staff applications for event.
- [ ] Multi-To Multi-Event circuits
- [ ] Accessibility: Fixed seating

## Dia de torneio

- **Equipa.** O dono do evento é o organizador; podem juntar-se outros pelo ecrã Equipa (`event_staff`) como
  `organizer`, `judge` ou `scorekeeper`. Cada papel só vê o que lhe cabe (`Organizer::OrganizerController`).
- **Confirmação de resultados.** Por evento: `none` (o resultado do organizador vale logo), `one` (basta um
  jogador da mesa confirmar) ou `all` (todos têm de confirmar). Com `self_report_enabled`, o vencedor regista o
  resultado em `/t/:slug/me`; os outros jogadores da mesa confirmam ou contestam. Um resultado pendente que
  ninguém confirma em `confirmation_timeout_minutes` passa a revisão da equipa (`Results::ExpirePendingJob`,
  corre de minuto a minuto); nunca é aceite automaticamente.
- **Juízes.** O jogador chama um juiz a partir da sua mesa; os pedidos aparecem no Centro de Juízes
  (`/organizer/tournaments/:id/judge_calls`), onde se reconhecem e fecham.
- **Página da ronda (organizador).** Toca numa linha de jogador para marcar o vencedor e depois confirma; há
  também Draw, +5 min de tempo extra por mesa e Tempo chamado, que decide a mesa pela regra
  `top_cut_timeout_rule`: `highest_seed_advances` (avança o melhor seed) ou `replay` (repetição com metade do
  tempo). "Fechar ronda" só funciona quando todas as mesas têm resultado, sem disputas nem juízes chamados (diz
  quais as mesas que bloqueiam); "Fazer o corte" cria o Top Cut e "Anular ronda" apaga as mesas e resultados.
- **Lista de inscritos.** Contadores no topo, check-in, pago, decklist, lista de espera (quando alguém desiste
  ou é libertado um lugar, `fill_from_waitlist!` chama o primeiro da fila), desistir e promover, e estatísticas
  expansíveis por linha.
- **Páginas públicas.** `/t/:slug/me` (a mesa e o lugar do jogador), a classificação em
  `/tournaments/:id/event_participants` (com a coluna Win %, também no telemóvel) e o cronómetro da ronda em
  `/t/:slug/timer`.
- **Impressões.** A partir da página da ronda: emparelhamentos (12 mesas por folha A4) e folhas com QR (6 por
  folha A4), que levam o jogador à sua mesa.
- **Aspeto.** Paleta A, apenas em modo escuro.

## Jogadores e público

- **Entrar.** Com e-mail e palavra-passe, ou com Google e Discord (OmniAuth, tabela `identities`). Variáveis de
  ambiente: `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` e `DISCORD_CLIENT_ID`/`DISCORD_CLIENT_SECRET`; sem elas o
  botão respetivo não aparece. Uma conta existente liga-se pelo e-mail verificado; o retorno é `/auth/:provider/callback`.
- **Conta (`/account`).** Nome, e-mail, palavra-passe, handle, país, bio, avatar, visibilidade do perfil
  (`public`, `participants` ou `private`) e identidades ligadas. Eliminar a conta anonimiza-a ("Removed player"):
  os resultados ficam, os dados pessoais saem. As miniaturas do avatar precisam de libvips: `brew install vips`.
- **Perfil público (`/p/:handle`).** Histórico com posição, V-D-E e lugares à mesa. A decklist só aparece se o
  evento tiver `show_decklists` e já estiver terminado. Ao terminar, cada torneio guarda a `final_position`
  (pontos do circuito).
- **Páginas públicas.** `/t/:slug` (evento, inscritos, lista de espera, inscrever e cancelar),
  `/t/:slug/pairings` (`?round=N`), `/t/:slug/standings` (com Win %) e `/t/:slug/timer`. Eventos em rascunho ou
  cancelados dão 404 a quem não é equipa; os antigos `/tournaments/:id` redirecionam.
- **Ao vivo.** Turbo Streams: a mesa de cada jogador e a página da ronda do organizador atualizam sozinhas
  (`Live::*Job`). Os emparelhamentos públicos ainda não são ao vivo.
- **Notificações.** `/notifications` e o sino no cabeçalho.
- **Feeds para o stream (OBS).** `/api/v1/events/:slug/standings`, `/rounds` e `/info`: JSON público, sem sessão,
  `Cache-Control: public, max-age=30`, ETag pela última alteração do evento e CORS `*` só em `/api/v1/*`. As chaves
  são as do relay TopDeck que o kit lia (`standings`, `rounds[].tables[]`, `latest`, `roundTime`, `timerEnd`); só
  rondas publicadas, sem byes nas mesas, `seed` = posição atual na classificação, rondas do corte como "Top 16".
  Nunca decklists nem links; comandantes só com `show_commanders_in_standings`. Rascunho ou cancelado → 404
  `{"error":"not_found"}`.
- **Desempenho.** Sprite de ícones local, Flowbite só no organizador, Leaflet local e carregado a pedido, fontes
  sem bloquear. `bin/rails "grindin:lighthouse[url]"` mede e falha abaixo de 90; resultados em
  `docs/superpowers/notes/2026-11-04-m3-lighthouse.md`.

Teste manual em telemóvel real (iOS e Android), por fazer:

1. Entrar com Google.
2. Abrir `/t/<slug>/me` e ver a mesa.
3. Reportar um resultado.
4. Abrir a classificação (`/t/<slug>/standings`).
5. Abrir o próprio perfil (`/p/<handle>`).

## Produção

- **Arquitectura.** Kamal 2 num VPS: imagem Docker em `ghcr.io/kakahpt/grindin-station`, kamal-proxy com HTTPS
  Let's Encrypt, Postgres/PostGIS como accessory preso a `127.0.0.1` (volume de dados e `config/postgres/init.sql`
  que cria as 4 bases), Active Storage no volume `/rails/storage` e Solid Queue dentro do Puma. Saúde em `/up`.
- **Feeds para o OBS.** `https://<domínio>/api/v1/events/<slug>/standings`, `.../rounds` e `.../info`: JSON público,
  cache de 30 s, CORS aberto, 120 pedidos por minuto por IP (depois 429), sem decklists, rondas do corte como "Top N".
  As chaves seguem o relay do TopDeck: `updated` em segundos epoch, `start`/`clock`/`end` por ronda, `ended` por mesa,
  `id` = UUID do jogador. O que o kit (`src/kit.js`) ainda tem de mudar:
  1. `const API` e o `fetch`: `https://<domínio>/api/v1/events/` + `<slug>/<feed>` em vez de `?feed=X&tid=Y`;
  2. `standingsTid`: o regex tem de aceitar o slug sozinho ou um link `/t/<slug>`;
  3. o feed `commanders` (`crew.php`) não tem equivalente: usar o `commander` do feed (com `show_commanders_in_standings`
     ligado no evento) ou desligar o autoCmd;
  4. o texto "Live from TopDeck".
  O resto (`json.standings`, `r.round`, `r.tables`, `t.*`, `p.seed`, `r.start/clock/end`, `t.ended`, `updated`) já
  coincide.
- **Segredos (GitHub, environment `production`).** Obrigatórios: `GS_VPS_HOST`, `GS_DOMAIN`, `RAILS_MASTER_KEY`,
  `POSTGRES_PASSWORD` (só hex: `openssl rand -hex 32`) e `SSH_PRIVATE_KEY`. Opcionais: `SSH_KNOWN_HOSTS`, OAuth
  (`GOOGLE_*`, `DISCORD_*`) e SMTP (`SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USER_NAME`, `SMTP_PASSWORD`;
  sem `SMTP_ADDRESS` não saem e-mails).
  `RAILS_MASTER_KEY` = o conteúdo de `config/master.key` nesta máquina (gerado em 2026-11-04, junto com o
  `config/credentials.yml.enc` novo; guarda-o no gestor de palavras-passe; sem ele a app não arranca; não está no git).
- **Primeiro deploy.** Com o DNS a apontar para o VPS: GitHub, Actions, Deploy, Run workflow, `command: setup`.
  Instala o Docker, arranca a base, constrói e envia a imagem e faz o primeiro deploy.
- **Organizador.** Nunca correr `db:seed` em produção (cria organizadores com palavra-passe conhecida; o
  `db/seeds.rb` aborta em produção). Criar a conta no site e promovê-la a organizador:
  `ssh root@$GS_VPS_HOST "docker exec -e EMAIL='tu@exemplo.pt' \$(docker ps -q -f label=service=grindin-station -f label=role=web) bin/rails runner 'EventOrganizer.find_or_create_by!(user: User.find_by!(email_address: ENV.fetch(\"EMAIL\")))'"`.
- **Deploy contínuo.** Cada push para `main` com a CI verde (que agora também constrói a imagem) corre `kamal deploy`.
- **Backups.** `bin/backup` corre todos os dias às 04:00 (cron, `config/backup.cron`), guarda 14 dumps e copia para
  fora do VPS se `RCLONE_REMOTE` estiver definido. `bin/restore <ficheiro>` repõe um dump (pede confirmação).
- **Por verificar.** Sem VPS e sem Docker no Mac, nada disto foi corrido a sério: `docker build`, Let's Encrypt,
  `init.sql`, workflow, cron e restore. Passos e checklist em
  [`docs/superpowers/notes/2026-11-04-m4-vps-checklist.md`](docs/superpowers/notes/2026-11-04-m4-vps-checklist.md).

## Setup no macOS

Testado em macOS (Apple Silicon) com `mise` e PostgreSQL 17 + PostGIS do Homebrew,
a correr em `127.0.0.1:5432` com o utilizador `postgres` / palavra-passe `postgres`.

```bash
mise install                  # Ruby 4.0.6 e Node 25.9.0 (ver mise.toml)
[ -f .env ] || printf 'DB_HOST=127.0.0.1\n' > .env   # só se ainda não existir
mise exec -- npm ci           # flowbite e plugins do Tailwind (node_modules)
mise exec -- bin/setup --skip-server
mise exec -- bin/rails test
```

Notas:

- **`npm ci` é obrigatório.** O build do Tailwind importa `flowbite/plugin` de
  `node_modules`; sem isso, `bin/rails test` (e `bin/dev`) falham com
  `Can't resolve 'flowbite/plugin'`. O `bin/setup` não instala dependências JS.
- **`gssencmode: disable` em `config/database.yml`.** Os testes correm em paralelo
  com `fork`. No macOS, o libpq tenta procurar credenciais Kerberos/GSSAPI ao
  ligar-se, e isso dentro de um processo filho faz rebentar o Ruby (`[BUG]
  Segmentation fault` em `pg/connection.rb`, `connect_start`) e a suite fica
  pendurada. A opção já está no bloco `default` de `config/database.yml`, por isso
  não é preciso pôr `PGGSSENCMODE` no `.env`; em ligações locais não se perde nada.
- A gem `pg` instala-se pré-compilada (`arm64-darwin`), por isso não é preciso
  `bundle config build.pg`. Se alguma vez for preciso compilá-la, usar
  `bundle config build.pg --with-pg-config=/opt/homebrew/opt/postgresql@17/bin/pg_config`.

## Motor do torneio

- **Pontos por evento.** Cada torneio guarda os seus pontos: vitória 7, empate 1, derrota 0, bye 7 (por omissão).
  O organizador pode mudá-los até o Swiss começar; quando o Swiss começa ficam bloqueados.
- **Rondas e cortes.** O formulário sugere rondas Swiss e corte pelo número de jogadores; o organizador pode
  mudar ambos antes do Swiss. Cortes possíveis: Top 4, 10, 13, 16 e 40 (ou sem corte).

  | Jogadores | 4–5 | 6–7 | 8–23 | 24–31 | 32–39 | 40–63 | 64–127 | 128+ |
  |---|---|---|---|---|---|---|---|---|
  | Rondas Swiss | 3 | 3 | 4 | 4 | 4 | 5 | 6 | 7 |
  | Corte | — | Top 4 | Top 4 | Top 10 | Top 13 | Top 16 | Top 16 | Top 40 |

- **Assentos justos (Swiss).** Em cada mesa, o assento 1 vai sempre para quem teve menos assentos 1 até agora.
  Entre essas ordens ganha a de menor custo: soma, por assento, de peso × (vezes que o jogador já lá se sentou)²,
  com pesos 3/1/1/2/2 para os assentos 1–5. Empates são sorteados com uma semente do evento, da ronda e da mesa,
  por isso a mesma semente dá os mesmos lugares. Cada lugar fica auditável: `assigned_by` (`fair` no Swiss,
  `ranked` no Top Cut, por ordem de classificação) e `cost`.
- **Desempates fixos**, por esta ordem: pontos; taxa de vitória dos adversários (a taxa de cada adversário nunca conta
  abaixo da de um empate); adversários batidos; adversários únicos; sorteio fixo por jogador, semeado pelo evento.
- **Reparação de reencontros.** Depois de emparelhar, trocam-se jogadores entre mesas enquanto o número de pares
  repetidos descer, primeiro com as mesas mais próximas e os jogadores de pontos mais próximos. Começa-se dentro do
  mesmo grupo de pontos; a diferença permitida só alarga (um empate, uma vitória, duas vitórias, …, qualquer) enquanto
  houver reencontros, por isso os líderes ficam nas primeiras mesas.
- **Distribuição por necessidade de assento.** Dentro de cada grupo de jogadores com os mesmos pontos, ordena-se
  pelo assento de que cada um mais precisa (o menos usado entre 1–4) e distribui-se um por mesa, para que cada
  mesa tenha necessidades diferentes. A classificação (e o Top Cut) não muda.

**Simulação.** `bin/rails "grindin:simulate[2000]"` (semente `SIM_SEED=42` por omissão) simula torneios de 16–140
jogadores e 4–7 rondas e compara os nossos lugares com lugares ao acaso. Medido a 27-10-2026:

| Lugares | Nunca no assento 1 | Diferença ≤ 1 entre assentos 1–4 |
|---|---|---|
| Ao acaso | 21 % | 18 % |
| Grindin Station | 1,1 % | 90 % |

A tarefa falha se piorar (nunca no assento 1 > 1,7 % ou diferença ≤ 1 < 87,7 %); a CI corre `grindin:simulate[500]`.
Os alvos ideais (ninguém sem assento 1, 99 %) ainda não são atingidos; ver
[`docs/superpowers/notes/2026-10-27-seat-simulation.md`](docs/superpowers/notes/2026-10-27-seat-simulation.md).

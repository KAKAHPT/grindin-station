# Grindin Station — especificação de desenho (v1)

Data: 2026-10-14 · Estado: para revisão do Kakah · Base: [PLANO.md](../../../PLANO.md)

## 1. Objetivo

Plataforma independente da cEDH PT para organizar torneios de cEDH (Commander competitivo, pods de 4), do anúncio
ao Top Cut, sem qualquer ligação ao TopDeck. Diferença central: **os assentos 1–4 do Swiss são distribuídos de forma
justa ao longo do torneio** e essa justiça é visível a todos.

Decisões já tomadas (14-10-2026):
- Código base: fork do Canivete (Rails 8, autor Fábio Batista, que concorda). Nome do produto: Grindin Station.
- Sem integração TopDeck (nem leitura nem escrita).
- Login por e-mail/palavra-passe, Google e Discord.
- Pagamentos: marcação manual "pago". Online fica para depois.
- Pontos por vitória/empate/derrota/bye **editáveis por evento**. Desempates **fixos**, só descritos.
- Alojamento: VPS Hostinger, Docker, deploy a partir do GitHub.
- Sem urgência; o Duelos Honra de 24-10 só se der. Qualidade primeiro.

## 2. Âmbito

**Na v1**
- Eventos (torneios) com estados: rascunho → inscrições abertas → inscrições fechadas → Swiss → Top Cut → terminado (ou cancelado).
- Inscrição por jogadores com conta; lista de espera quando o limite é atingido; check-in; marcação "pago"; drop.
- Swiss em pods de 4 (3 ou 5 quando o número não divide), com nº de rondas e corte sugeridos pelo tamanho e alteráveis antes do início.
- Assentos justos no Swiss; no Top Cut, ordem pela classificação.
- Resultados: reportados pelo organizador/juiz, ou por um jogador da mesa; confirmação pelos outros configurável (nenhuma, um, todos), com "contestar" sempre disponível.
- Standings com os desempates fixos e a contagem de assentos por jogador.
- Chamada de juiz por mesa; penalizações (sistema do Canivete); timer de ronda em ecrã grande; tempo extra por mesa.
- Páginas públicas mobile: evento, lista de inscritos, a minha mesa/assento (ao vivo), standings, histórico do jogador.
- Feeds JSON para o kit de stream (OBS), com o formato que o kit já lê.
- Interface em inglês (predefinição) e português de Portugal como segunda opção (pedido de 14-10-2026).

**Fora da v1** (fica no código do Canivete mas sem trabalho nem garantia): ligas, wagers, circuitos. Não se faz:
pagamentos online, verificador de decklists, metagame, mensagens em massa, página de "hub"/descoberta.

**Planeado para a v2 — rede social de jogadores** (pedido de 14-10-2026): perfis públicos ricos, amigos / seguir
mutuamente, comentários (em eventos e perfis), feed de atividade e notificações. Não se constrói na v1, mas a v1 nasce
preparada (ver §4 "Preparação para a v2" e §6): cada jogador é uma entidade pública com `handle` único, há uma tabela
genérica de notificações desde o início, e as regras de privacidade (quem vê o quê) são campos do jogador e não lógica
espalhada.

**Planeado para a v3 — Judge Bot** (pedido de 17-10-2026): um assistente de regras dentro de cada torneio, numa
área de chat que os jogadores consultam. Responde a dúvidas de regras e de procedimento de torneio e **toda a resposta
traz obrigatoriamente a fonte** (documento, secção/número da regra e ligação); sem fonte, não responde e sugere chamar
o juiz. Fontes previstas: as regras oficiais (Comprehensive Rules, regras do formato Commander, MTR/IPG), as
regras da cEDH PT e o material dos juízes de Portugal / da Europa publicado no GitHub (repositório a confirmar com os
juízes), tudo versionado e lido por data de evento. Integra com o Judge Center: um botão "não resolveu, chamar juiz"
abre uma `judge_call` com o histórico da conversa. Não decide nada: é apoio, o juiz humano prevalece, e a interface
diz isso. Preparação na v1: nenhuma estrutura nova; a tabela `notifications` genérica e `judge_calls` já chegam. Fica
documentado aqui para que o modelo de eventos/juízes não se feche a isto.

## 3. Arquitetura

- **Stack:** Ruby 4.0.6, Rails 8.1, PostgreSQL 17 + PostGIS, Hotwire (Turbo + Stimulus), Tailwind 4, Solid Queue/Cache/Cable, Propshaft, Importmap. Tudo herdado do Canivete.
- **Repositório:** a base é o **vosso fork `KAKAHPT/canivete`** (não o repositório do Fábio, que fica intocado e sem
  qualquer ligação). Cria-se `KAKAHPT/grindin-station` por `git clone` desse fork, com o histórico intacto; o único
  remoto é o novo repositório. Ramo principal `main`. Adicionar `LICENSE` acordada com o Fábio (proposta: MIT, com os
  dois nomes) e `CREDITS.md` a reconhecer a origem.
- **Camadas:** modelos (domínio), serviços em `app/services/` (emparelhamento, assentos, standings, cortes), jobs (Solid Queue) para começar/terminar rondas, controladores em três espaços: público, `organizer/` e `judge/`.
- **Tempo real:** Turbo Streams por Solid Cable. Ao publicar uma ronda, as páginas "a minha mesa" e o timer recebem a atualização sem recarregar.
- **Dev local:** mise (Ruby/Node), Homebrew `postgresql@17` + `postgis`; `bin/setup`, `bin/dev`. Sem Docker no Mac.
- **Produção:** VPS Hostinger (Ubuntu), Docker com Kamal (já configurado no Canivete): contentor da app + Postgres/PostGIS + proxy com TLS. Backups diários do Postgres para o storage da Hostinger. Deploy por GitHub Actions no push a `main` depois dos testes passarem.

## 4. Modelo de dados (diferenças face ao Canivete)

Mantém-se: `users`, `players`, `event_organizers`, `events` (STI: Tournament/League), `event_participants`, `rounds`
(SwissRound/SingleEliminationRound), `pods`, `seatings`, `results` (STI), `infractions`, `rooms`, `circuits`.

Alterações:
- `events`: `points_win` (7), `points_draw` (1), `points_loss` (0), `points_bye` (7), `swiss_rounds_count`, `top_cut_size`
  (4/10/16/40), `round_minutes` (80), `top_cut_round_minutes` (150), `max_participants`, `waitlist_enabled`,
  `self_report_enabled` (true), `result_confirmation` (none | one | all; predefinição none; alterável a qualquer momento),
  `locale` (predefinição "en"). Os quatro campos de pontos ficam bloqueados quando o Swiss começa.
- `event_participants`: `waitlisted` (bool), `waitlist_position`, `seat_counts` (jsonb `{ "1": n, … "5": n }`, cache
  recalculada ao publicar cada ronda), `tiebreak_cache` (jsonb, recalculada ao terminar cada ronda).
- `seatings`: `assigned_by` ("fair" | "ranked" | "manual") e `cost` (número, para auditoria).
- `pods`: `reported_by_participant_id`, `reported_at`, `confirmations` (jsonb: participant_id → timestamp), `disputed` (bool).
- Nova `judge_calls`: `pod_id`, `participant_id`, `reason`, `status` (open/acknowledged/closed), timestamps.
- Nova `identities` (OAuth): `user_id`, `provider` (google|discord), `uid`, `email`. Um user pode ter várias.
- Nova `event_staff`: `event_id`, `user_id`, `role` (organizer|judge|scorekeeper).
- `users`: `locale`, `avatar_url`.
- Todos os registos de assento e resultado são imutáveis depois de a ronda terminar; correções criam um registo novo com `superseded_by`.

**Preparação para a v2 (social), feita já na v1:**
- `players`: `handle` (único, URL `/p/:handle`), `display_name`, `bio`, `country`, `avatar`, `visibility`
  (public | players_only | private) e `allow_follows`, `allow_comments` (booleanos, predefinição true). O perfil público da v1 já usa estas regras.
- Nova `notifications` genérica desde a v1: `user_id`, `kind` (result_confirmation, judge_call, round_published, …),
  `subject_type/subject_id` (polimórfico), `read_at`. A v1 usa-a para confirmações de resultado, chamadas de juiz e
  publicação de rondas; a v2 acrescenta `follow`, `comment`, `friend_request` sem mudar a tabela.
- Tabelas da v2 **só desenhadas, não criadas**: `follows` (`follower_id`, `followed_id`, `status`: pending | accepted,
  único por par; "amigos" = dois follows aceites) e `comments` (`author_id`, `subject_type/subject_id` polimórfico,
  `body`, `deleted_at`, moderação por organizadores). Nada na v1 pode assumir que um jogador tem um só user ou um só evento.
- Eliminação de conta (RGPD) já na v1 apaga identidades, notificações e perfil e anonimiza resultados; na v2 a mesma rotina apaga follows e comentários.

## 5. Motor do torneio

### 5.1 Rondas e corte
- Sugestão por nº de jogadores (alterável antes de começar):

| Jogadores | Rondas Swiss | Corte |
|---|---|---|
| 4–7 | 3 | Top 4 (ou só Swiss se 4–5) |
| 8–23 | 4 | Top 4 |
| 24–31 | 4 | Top 10 |
| 32–39 | 4 | Top 13 |
| 40–63 | 5 | Top 16 |
| 64–127 | 6 | Top 16 |
| 128–255 | 7 | Top 40 |

- Cortes suportados: **Top 4** (final direta); **Top 10** (seeds 1–2 passam à final, seeds 3–10 em 2 pods, os 2 vencedores
  completam a final); **Top 13** (seed 1 passa à final, seeds 2–13 em 3 pods, os 3 vencedores completam a final);
  **Top 16** (4 pods, vencedores à final); **Top 40** (seeds 1–8 passam, seeds 9–40 em 8 pods,
  8 vencedores + 8 seeds = 16 → 4 pods → final). Pods do corte formados em serpentina pelos seeds (1,8,9,16 / 2,7,10,15 …).
  Na tabela de sugestões, 24–31 jogadores → Top 10 e 32–39 → Top 13; o organizador escolhe qualquer corte que o nº de jogadores permita.
- Nos pods do corte não há empate: se o tempo acaba, aplica-se a regra do evento (configurável: o seed mais alto avança, ou repetição com tempo reduzido). Predefinição: seed mais alto avança.

### 5.2 Emparelhamento Swiss
- Herdado do Canivete: ordenação por pontos e desempates, pods por "standard" (adjacentes), "spread" (serpentina na 2ª ronda) e "forced" (última ronda, sem repetir adversários salvo impossibilidade). Pods de 3/5 conforme `bye_mode` (predefinição: pod de 3 nos últimos lugares, como a cEDH PT usa hoje); bye verdadeiro só se o organizador o escolher.
- Regra nova obrigatória: o histórico de assentos **nunca** influencia quem joga com quem. Só influencia a ordem dentro da mesa.
- Antes de qualquer alteração, escrevem-se testes do comportamento atual (adjacência por pontos, não repetição, pods de 3/5, drops) e ficam verdes.

### 5.3 Assentos justos (Swiss) — `Tournaments::SeatAssigner`
Entrada: um pod com N jogadores (3–5) e, para cada um, `seat_counts` das rondas Swiss anteriores (byes não contam; pods de 3/5 contam na posição real). Saída: uma ordem 1..N.

Algoritmo:
1. Gerar as N! ordens possíveis (24 para 4; 120 para 5).
2. Custo de uma ordem = Σ sobre jogadores de `w[assento] × (vezes que já foi nesse assento)²`, com pesos
   `w = {1: 3, 2: 1, 3: 1, 4: 2, 5: 2}`.
3. Regra de prioridade dura: o assento 1 vai a um jogador com o **menor** nº de vezes no assento 1 nessa mesa. Entre ordens que a respeitam, ganha a de menor custo.
4. Empates de custo: sorteio com semente guardada no evento (reprodutível).
5. Gravar em cada `seating` o custo e `assigned_by = "fair"`. O organizador pode alterar à mão (`manual`), e fica registado.
6. Top Cut: `ranked` — seed mais alto no assento 1, e assim sucessivamente. Sem otimização.

Garantias e medição:
- Objetivo: ninguém fica sem o assento 1 num torneio de ≥ 4 rondas; diferença máxima entre contagens de qualquer assento de um jogador ≤ 1 em ≥ 99 % dos torneios simulados.
- Tarefa `bin/rails grindin:simulate` corre 10 000 torneios aleatórios (16–140 jogadores, 4–7 rondas, resultados aleatórios com 30 % de empates) e imprime: % de jogadores sem assento 1, distribuição da diferença máxima, pior caso. Corre no CI e falha se o objetivo não for cumprido.
- Standings públicos mostram, por jogador, "1·2·3·4: 2·1·1·1".

### 5.4 Pontuação e standings
- Pontos por evento: vitória 7, empate 1, derrota 0, bye = vitória (editáveis até o Swiss começar). Pod de 3/5: os mesmos pontos (sem escala por tamanho).
- **Desempates fixos**, nesta ordem, só sobre rondas Swiss:
  1. **Pontos de match.**
  2. **Win rate dos adversários (pontos/máximo):** para cada adversário real (sem byes nem "fantasmas"), `pontos ÷ (rondas jogadas × pontos por vitória)`, com mínimo 1/7 (≈ 0,1429, o valor de um empate); média simples.
  3. **Adversários batidos:** número de jogadores distintos que estavam na mesa em cada vitória tua.
  4. **Adversários únicos:** número de jogadores distintos com quem jogaste.
  5. Persistindo empate: sorteio com a semente do evento, fixado na 1ª ronda e mantido.
- Os desempates aparecem explicados numa página "Como funcionam os standings" e em tooltip nos cabeçalhos. Não são editáveis.
- Standings e `tiebreak_cache` recalculam-se ao fechar cada ronda; páginas públicas leem a cache.

### 5.5 Resultados
- Quem reporta: organizador/juiz/scorekeeper sempre; um jogador da mesa se `self_report_enabled`.
- Auto-reporte: um jogador da mesa marca o vencedor (normalmente o próprio) ou empate. O que acontece a seguir depende
  de `result_confirmation`, **editável por evento, mesmo a meio do torneio**:
  - `none` (**predefinição**): o resultado fecha o pod de imediato. Os outros três veem-no na sua página e têm um botão
    "contestar", que marca `disputed` e avisa o Judge Center; o pod continua fechado até um juiz decidir.
  - `one`: basta mais um jogador da mesa confirmar para fechar.
  - `all`: os outros três têm de confirmar (para eventos onde se queira esse rigor).
  - Em `one` e `all`, passado o timeout (predefinição 5 min) o pod passa a "a rever" e o staff fecha-o.
- Staff pode sempre reportar, corrigir ou sobrepor-se, independentemente do modo. Toda a disputa é resolvida pelo staff; o sistema só a regista.
- Ronda termina quando todos os pods têm resultado; o organizador clica "fechar ronda" (não é automático), o que publica standings e permite "nova ronda" / "fazer corte".
- Correção depois de fechado: só staff; cria resultado novo, mantém o antigo como `superseded`, recalcula standings; se já há ronda seguinte publicada, avisa que os pods seguintes podem ficar errados e exige confirmação.

### 5.6 Drops, atrasos, no-shows
- Drop antes de a ronda ser publicada: sai do emparelhamento. Depois de publicada: fica na mesa, conta como derrota, sai na seguinte.
- No-show no check-in: organizador marca; é tratado como drop.
- Inscrição tardia: só até o Swiss começar.

## 6. Pessoas e permissões

- **Contas:** e-mail + palavra-passe (bcrypt, já existe), Google e Discord via OmniAuth; ligação de várias identidades ao mesmo user por e-mail igual, ou manual na página de conta. Recuperação por e-mail. Eliminação de conta com anonimização dos resultados (o nome passa a "Jogador removido", os pontos ficam).
- **Papéis:** jogador (qualquer conta); organizador (cria eventos; `event_organizers`); staff por evento: organizer, judge, scorekeeper. Juiz: Judge Center (chamadas, penalizações, resultados); scorekeeper: resultados e check-in.
- **Perfil público** (`/p/:handle`): nome, handle, país opcional, bio, avatar, histórico de eventos com posição e assentos, respeitando `visibility`. Decklist por evento só se o organizador ativar "mostrar decklists" (sempre depois do evento acabar). Botões "seguir" e comentários ficam para a v2, mas o layout reserva-lhes o lugar.

## 7. Interfaces

**Organizador** (desktop first): lista de eventos; criar/editar (dados, pontos, rondas/corte sugeridos, timer, bye mode, auto-reporte, limite/lista de espera); roster (pesquisa, check-in, pago, drop, decklist, adicionar à mão); rondas (publicar, ver pods com assentos, trocar jogadores ou assentos à mão, resultados, tempo extra por mesa, fechar ronda); corte; standings; Judge Center (chamadas abertas, penalizações); staff; timer em ecrã grande (`/t/:slug/timer`, só o relógio e o nome da ronda); impressão de emparelhamentos (A4, por mesa) e de "slips" por mesa com QR.

**Jogador** (mobile first): evento público (descrição, local, data, preço, regras, inscritos/lista de espera); inscrever-se/anular; "a minha mesa" (mesa, assento, nomes, comandantes dos outros se publicados; atualiza ao vivo); reportar/confirmar resultado; chamar juiz; standings com assentos; perfil.

**Público sem login:** evento, inscritos, pods da ronda atual, standings, resultados finais.

## 8. Feeds para o stream (OBS)

Sem autenticação, cache 30 s, CORS aberto, mesmas chaves que o kit lê hoje do cedhpt.com:
- `GET /api/v1/events/:slug/standings` → `{tid, name, updated, players:[{rank,name,commander,wins,losses,draws,points,seats:{1:n,…}}]}`
- `GET /api/v1/events/:slug/rounds` → `{tid, updated, roundTime, latest, rounds:[{round, tables:[{table,status,winner,draw,players:[{name,commander,seed}]}]}]}`
  Jogadores em ordem de assento; `round` numérico no Swiss e "Top 16"/"Top 4" no corte.
- `GET /api/v1/events/:slug/info` → nome, datas, estado, nº de jogadores, ronda atual, fim previsto do timer.
Decklists nunca saem por aqui.

## 9. Testes e qualidade

- Minitest, como no Canivete. Novos testes obrigatórios: emparelhamento (comportamento atual congelado), `SeatAssigner` (casos de 3/4/5, regra de prioridade, empates), standings/desempates (casos calculados à mão a partir do MidSeason 2026: a ordem final tem de bater certo com a do TopDeck, exceto onde o TopDeck usou o sorteio), auto-reporte nos três modos de confirmação e contestação, drops, cortes Top 4/10/13/16/40.
- Simulação `grindin:simulate` no CI (§5.3).
- Testes de sistema (Capybara) para os três fluxos críticos: criar evento e publicar ronda 1; jogador vê a mesa e reporta; organizador fecha ronda e faz corte.
- Rubocop e Brakeman no CI. Prosopite para N+1 em dev.

## 10. Marcos (cada um termina com verificação)

- **M0 — Base:** repositório criado, ambiente local a funcionar, testes do Canivete verdes, rename para Grindin Station, pt-PT. Verificar: `bin/rails test` verde; `bin/dev` abre a app em português.
- **M1 — Motor:** testes do emparelhamento, `SeatAssigner`, pontos por evento, desempates fixos, cortes 4/10/13/16/40, simulação a cumprir o objetivo. Verificar: CI verde; replay do MidSeason 2026 reproduz a classificação final do TopDeck.
- **M2 — Dia de torneio:** roster/check-in/lista de espera, rondas com assentos, resultados com auto-reporte, confirmação configurável e contestação, chamada de juiz, timer, impressões, fecho de ronda e corte. Verificar: teste de sistema dos três fluxos; ensaio com 16 contas de teste em dois portáteis e telemóveis.
- **M3 — Jogadores e público:** OAuth Google/Discord, páginas mobile, "a minha mesa" ao vivo, perfis, standings com assentos. Verificar: Lighthouse mobile ≥ 90 nas páginas de jogador; teste em iOS e Android reais.
- **M4 — Produção:** VPS Hostinger, Kamal, TLS, backups, GitHub Actions, feeds para o OBS ligados ao kit. Verificar: kit de stream a mostrar standings de um evento de teste no Grindin Station.
- **M5 — Piloto:** torneio local de 20–40 jogadores, com registo em papel como rede de segurança. Verificar: evento terminado sem intervenção manual na base de dados; relatório do que correu mal.

## 11. Riscos

- Dependência do Rails numa equipa pequena: mitigado por Fábio a bordo, testes e documentação em pt.
- Emparelhamento do Canivete sem testes: congelar comportamento antes de tocar (M1).
- Colisões de assento inevitáveis em rondas 5+: medidas pela simulação e visíveis nos standings; aceitar diferença 1.
- Reporte sem confirmação (modo `none`) permite um resultado errado fechar um pod: mitigado pelo botão "contestar" dos outros três, pelo Judge Center e pelas correções auditáveis do staff.
- Rede fraca no local: páginas leves, sem dependências externas de CDN em runtime, timer funciona offline depois de carregado.

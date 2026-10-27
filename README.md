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
  O organizador pode mudá-los até ao fecho das inscrições; quando o Swiss começa ficam bloqueados.
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
  repetidos descer. Nas rondas normais só se troca dentro do mesmo grupo de pontos; nas rondas spread e forced,
  entre quaisquer pontos.
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

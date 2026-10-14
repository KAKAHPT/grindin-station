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

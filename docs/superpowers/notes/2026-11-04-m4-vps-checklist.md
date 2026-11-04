# M4 — Checklist manual do VPS e do primeiro deploy

Nada disto foi executado pelo agente: tudo o que precisa de credenciais, DNS ou acesso ao VPS fica para o utilizador.
Ficheiros de referência: `config/deploy.yml`, `.kamal/secrets`, `config/postgres/init.sql`, `.github/workflows/deploy.yml`,
`bin/backup`, `bin/restore`, `config/backup.cron`.

## 1. VPS (Hostinger)

- [ ] Criar um VPS **Ubuntu 24.04** (x86_64/amd64 — a imagem é construída para `amd64`). 2 GB de RAM no mínimo.
- [ ] Firewall (painel da Hostinger e/ou `ufw`): abrir só **22**, **80** e **443**. A porta 5432 do Postgres fica em `127.0.0.1` e não deve ser aberta.
- [ ] Anotar o IP público → será o segredo `GS_VPS_HOST`.
- [ ] (Opcional) `apt install docker.io` — o `kamal setup` instala o Docker se faltar, desde que o utilizador SSH seja `root`.

## 2. DNS

- [ ] Registo **A** `GS_DOMAIN` (ex.: `grindin.cedhpt.com`) → IP do VPS. Esperar que propague (`dig +short GS_DOMAIN`) **antes** do primeiro deploy: o kamal-proxy pede o certificado Let's Encrypt no arranque.
- [ ] Se usar Cloudflare: proxy desligado (nuvem cinzenta) no primeiro deploy, ou SSL/TLS em modo "Full".

## 3. Chave SSH para o deploy

- [ ] `ssh-keygen -t ed25519 -C "grindin-station deploy" -f ~/.ssh/grindin_deploy` (sem passphrase, é para o GitHub Actions).
- [ ] Adicionar `~/.ssh/grindin_deploy.pub` a `/root/.ssh/authorized_keys` no VPS (`ssh-copy-id -i ~/.ssh/grindin_deploy.pub root@GS_VPS_HOST`).
- [ ] Testar: `ssh -i ~/.ssh/grindin_deploy root@GS_VPS_HOST true`.

## 4. Segredos no GitHub (Settings → Environments → `production` → Secrets)

O workflow usa `environment: production`; os segredos podem estar no environment ou no repositório.

| Segredo | Obrigatório | Valor |
|---|---|---|
| `GS_VPS_HOST` | sim | IP do VPS |
| `GS_DOMAIN` | sim | domínio público (sem `https://`) |
| `RAILS_MASTER_KEY` | sim | conteúdo de `config/master.key` |
| `POSTGRES_PASSWORD` | sim | `openssl rand -hex 32` (só hex: entra nos URLs da base de dados sem escape) |
| `SSH_PRIVATE_KEY` | sim | conteúdo de `~/.ssh/grindin_deploy` (privada) |
| `SSH_KNOWN_HOSTS` | não (recomendado) | saída de `ssh-keyscan -H $GS_VPS_HOST` (corrida uma vez a partir do Mac, depois de confirmar a impressão digital no painel da Hostinger). Sem ele o workflow faz `ssh-keyscan` em cada deploy |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | não | OAuth Google; redirect `https://GS_DOMAIN/auth/google_oauth2/callback` |
| `DISCORD_CLIENT_ID` / `DISCORD_CLIENT_SECRET` | não | OAuth Discord; redirect `https://GS_DOMAIN/auth/discord/callback` |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USER_NAME`, `SMTP_PASSWORD` | não | e-mail de saída (reposição de palavra-passe). Sem `SMTP_ADDRESS` os e-mails não são enviados |

- No GitHub Actions o registo `ghcr.io` usa o `GITHUB_TOKEN` (permissão `packages: write` já no workflow); não é preciso PAT.
  A imagem tem `LABEL org.opencontainers.image.source` a apontar para o repositório, por isso o pacote fica ligado a ele.
- Se o primeiro push da imagem tiver sido feito com um PAT (deploy à mão): GitHub → Packages → `grindin-station` →
  Package settings → **Manage Actions access** → adicionar o repositório `grindin-station` com **Write**.
- Para um deploy **à mão** a partir do Mac, `KAMAL_REGISTRY_PASSWORD` = PAT clássico com `write:packages` (e `read:packages`).
- O workflow falha logo no passo "Check required secrets" com a lista dos segredos obrigatórios em falta.

## 5. Primeiro deploy (pelo GitHub Actions — o Mac não tem Docker)

- [ ] Fazer merge de `m4` em `main` (o workflow **Deploy** só aparece/dispara a partir do branch por omissão).
- [ ] GitHub → Actions → **Deploy** → **Run workflow** → `command: setup`. Isto instala o Docker no VPS, arranca o
      accessory `db` (o `init.sql` cria as 4 bases), constrói e envia a imagem para `ghcr.io` e faz o primeiro deploy.
- [ ] Ver os logs da base: na máquina local, com as mesmas variáveis exportadas (`GS_VPS_HOST`, `GS_DOMAIN`), `bin/kamal accessory logs db`
      — ou `ssh root@$GS_VPS_HOST 'docker logs grindin-station-db'`.
- [ ] **Nunca correr `db:seed` em produção** (os seeds criam organizadores com palavra-passe conhecida; `db/seeds.rb`
      aborta se `RAILS_ENV=production`).
- [ ] Criar o organizador real: criar a conta no site (`https://$GS_DOMAIN/registrations/new`), depois promovê-la
      (trocar `tu@exemplo.pt` pelo e-mail com que te registaste):

      ```sh
      ssh root@$GS_VPS_HOST "docker exec -e EMAIL='tu@exemplo.pt' \$(docker ps -q -f label=service=grindin-station -f label=role=web) bin/rails runner 'EventOrganizer.find_or_create_by!(user: User.find_by!(email_address: ENV.fetch(\"EMAIL\")))'"
      ```

      (Ou, numa máquina com as variáveis exportadas, sem Docker local:
      `EMAIL=tu@exemplo.pt; bin/kamal app exec -i --reuse "bin/rails runner 'EventOrganizer.find_or_create_by!(user: User.find_by!(email_address: \"$EMAIL\"))'"`.)
      Depois disso essa conta já pode criar eventos.
- [ ] `curl -fsS https://$GS_DOMAIN/up` → 200 com certificado válido.
- [ ] Iniciar sessão, criar um evento de teste, carregar um avatar (confirma `libvips` e o volume `grindin_storage`).
- [ ] A partir daqui, cada push para `main` com CI verde (incluindo o job `docker`) faz `bin/kamal deploy` automaticamente.
      "Run workflow" com `command: deploy` serve para um redeploy manual.

## 6. Backups

A partir do Mac (na raiz do repositório, com `GS_VPS_HOST` exportado):

```sh
ssh root@$GS_VPS_HOST 'mkdir -p /opt/grindin-station/bin /var/backups/grindin-station'
scp bin/backup bin/restore root@$GS_VPS_HOST:/opt/grindin-station/bin/
ssh root@$GS_VPS_HOST 'chmod +x /opt/grindin-station/bin/backup /opt/grindin-station/bin/restore'
ssh root@$GS_VPS_HOST '/opt/grindin-station/bin/backup'           # primeiro dump à mão
ssh root@$GS_VPS_HOST 'ls -lh /var/backups/grindin-station'
```

- [ ] Instalar o cron: `crontab -e` no VPS e colar a linha de `config/backup.cron` (todos os dias às 04:00 UTC, mantém 14 dumps).
- [ ] (Opcional, recomendado) cópia fora do VPS: instalar `rclone`, `rclone config` com um bucket S3-compatível (Backblaze B2, Cloudflare R2, …) e acrescentar `RCLONE_REMOTE=remote:bucket` à linha do cron.
- [ ] Os dumps contêm só a base primária (`grindin_station_production`); cache/queue/cable são recriáveis. Os ficheiros do Active Storage estão no volume Docker `grindin_storage` — incluir `/var/lib/docker/volumes/grindin_storage` num backup do VPS (snapshot da Hostinger) se os avatares importarem.

## 7. Testar o restore (antes de haver dados reais)

```sh
ssh root@$GS_VPS_HOST 'docker stop $(docker ps -q -f label=service=grindin-station -f label=role=web)'
ssh -t root@$GS_VPS_HOST '/opt/grindin-station/bin/restore /var/backups/grindin-station/<ficheiro>.dump'
# depois: Actions → Deploy → Run workflow → deploy (ou bin/kamal app boot com as variáveis exportadas)
```

- [ ] O restore pede confirmação (escrever o nome da base), corre numa só transacção e pára no primeiro erro;
      a app volta com os dados do dump.

## O que ficou por verificar nesta máquina

- `docker build` / `bin/docker-smoke`: o Docker não está instalado no Mac de desenvolvimento ("docker not available").
  O job `docker` do CI constrói a imagem e arranca o ambiente de produção sem base de dados em cada push/PR.
- `kamal setup`/`deploy`, Let's Encrypt, `init.sql` no Postgres real, cron e restore: só no VPS.

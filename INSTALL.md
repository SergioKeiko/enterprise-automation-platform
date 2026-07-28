# Installation Guide

This guide takes you from **nothing** to a **fully working automation stack**
in about 1.5 hours. Every step tells you exactly what to type or click, and
how to check that it worked before moving on.

**You will need:**

- **Any VPS provider** — Hetzner, DigitalOcean, Vultr, Contabo, OVH, AWS…
  The stack only needs a server with **Ubuntu (newest LTS), 2+ vCPU, 8 GB RAM
  (4 GB minimum), x86**. This guide shows Hetzner's screens (~€16/mo there);
  on any other provider do the equivalent clicks — they all have the same
  concepts: server, SSH key, firewall.
- A domain whose DNS is managed by [Cloudflare](https://dash.cloudflare.com) (free plan is enough).
  If your domain is elsewhere, [move its nameservers to Cloudflare](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/) first (~15 min).
- A terminal: **macOS/Linux** — the built-in Terminal app. **Windows** — install
  [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) and use the Ubuntu terminal.

> 🇺🇦 Українська версія цієї інструкції: [docs/uk/INSTALL.md](docs/uk/INSTALL.md)

---

## Step 1 — Create an SSH key and a server

An SSH key is how you log in to your server without a password.

**1.1.** In your terminal, create a key (press Enter for every question):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/automation-server
```

**1.2.** Print the public key and copy the whole output line:

```bash
cat ~/.ssh/automation-server.pub
```

**1.3.** Add the public key to your provider. On Hetzner:
[Console](https://console.hetzner.cloud) → your project → **Security** (left
menu) → **SSH keys** → **Add SSH key** → paste the copied line → name it
`my-laptop` → **Add SSH key**.
*(Other providers: every server-creation form has an "SSH key" field — paste
the same line there.)*

**1.4.** Create the server. On Hetzner: **Servers** → **Add server**:

| Setting | Value |
|---|---|
| Location | Nuremberg (or the one closest to you) |
| Image | **Ubuntu** — the newest LTS offered (e.g. 24.04 or 26.04) |
| Type | Shared vCPU (x86) → **CPX31** (4 vCPU / 8 GB) |
| SSH key | tick `my-laptop` |
| Name | `automation-server` |

Leave everything else at defaults → **Create & Buy now**.

*(Other providers: pick the equivalent — Ubuntu newest LTS, x86, 2+ vCPU,
8 GB RAM — and attach your SSH key.)*

**1.5.** Copy the server's IP address from the server list (looks like `65.108.xx.xx`).
In the commands below, replace `YOUR_SERVER_IP` with it every time.

**✅ Check:** this command must open a `root@automation-server:~#` prompt:

```bash
ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP
```

(Type `yes` when asked about the fingerprint. Type `exit` to leave; but stay
logged in — the next steps happen partly on the server.)

> Some providers log you in as a different user (AWS: `ubuntu`, some others:
> `debian`/`admin`). In that case connect with that username and run `sudo -i`
> right after logging in — the rest of the guide assumes you are root.

---

## Step 2 — Firewall

Close every port except the ones the stack needs. Use your **provider's**
firewall (it filters traffic before it reaches the server — more reliable than
a firewall on the server itself, which Docker partially bypasses).

**2.1.** On Hetzner: Console → **Firewalls** (left menu) → **Create Firewall**.
*(DigitalOcean: Networking → Firewalls. Vultr: Firewall. AWS: Security Groups.
The rules are the same everywhere.)*

**2.2.** Add these **inbound** rules (leave "Any IPv4/IPv6" as source):

| Protocol | Port | Purpose |
|---|---|---|
| TCP | 22 | SSH (you) |
| TCP | 80 | HTTP (certificates) |
| TCP | 443 | HTTPS (all services) |
| ICMP | — | ping |

**2.3.** Apply the firewall to your server (on Hetzner: **Apply to** →
select `automation-server` → **Create Firewall**).

> If your provider has no cloud firewall, you can continue without one:
> every exposed service in this stack requires a password or API key anyway.
> Add a firewall later if the provider introduces one.

> Later, if an external app (e.g. hosted on Vercel) needs to connect
> **directly** to the Supabase database pooler or API, also allow TCP 6543
> and/or TCP 8000. Don't open them "just in case".

**✅ Check:** you can still log in over SSH (rule 22 works):

```bash
ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP
```

---

## Step 3 — Cloudflare: DNS records and API token

**3.1.** In [Cloudflare Dashboard](https://dash.cloudflare.com) open your
domain → **DNS** → **Records**. Create **4 records**, one per service:

| Type | Name | IPv4 address | Proxy status |
|---|---|---|---|
| A | `n8n` | YOUR_SERVER_IP | 🟠 Proxied |
| A | `supabase` | YOUR_SERVER_IP | 🟠 Proxied |
| A | `qdrant` | YOUR_SERVER_IP | 🟠 Proxied |
| A | `uptime` | YOUR_SERVER_IP | 🟠 Proxied |

**3.2.** Create an API token (Traefik uses it to prove domain ownership to
Let's Encrypt): click the profile icon (top-right) → **My Profile** →
**API Tokens** → **Create Token** → **Create Custom Token**:

- Token name: `traefik-dns`
- Permissions: **Zone** → **DNS** → **Edit**
- Zone Resources: **Include** → **Specific zone** → your domain
- **Continue to summary** → **Create Token**

**Copy the token now** — Cloudflare shows it only once. You'll paste it in Step 6.

**✅ Check:** in your terminal (on your computer):

```bash
nslookup n8n.YOUR_DOMAIN
```

It must return IP addresses (Cloudflare's, not your server's — that's correct,
the proxy hides your server IP).

---

## Step 4 — Install Docker on the server

Log in to the server (`ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP`)
and run:

```bash
apt update && apt upgrade -y
```

```bash
curl -fsSL https://get.docker.com | sh
```

Create the shared network that connects Traefik with all services:

```bash
docker network create proxy
```

**✅ Check:**

```bash
docker --version && docker compose version && docker network ls | grep proxy
```

You should see a Docker version, a Compose version, and a line with `proxy`.

---

## Step 5 — Get the code

Still on the server:

```bash
cd /root && git clone https://github.com/SergioKeiko/enterprise-automation-platform.git
```

```bash
cd /root/enterprise-automation-platform
```

Create the (empty for now) certificate storage file with strict permissions —
Traefik refuses to start without this:

```bash
touch n8n-stack/traefik/acme.json && chmod 600 n8n-stack/traefik/acme.json
```

Create the n8n data folder owned by the container user (n8n runs as user 1000
inside the container and crashes if the folder belongs to root):

```bash
mkdir -p n8n-stack/data && chown 1000:1000 n8n-stack/data
```

**✅ Check:** `ls -a n8n-stack` shows `docker-compose.yml`, `traefik`, `.env.example`.

---

## Step 6 — Generate all secrets

One script asks 4 questions and generates every password and key the stack
needs (there are 10+ of them — don't do this by hand):

```bash
bash scripts/generate-secrets.sh
```

It will ask for:

1. **Your base domain** — e.g. `example.com` (no `https://`, no subdomain)
2. **Your e-mail** — used only for Let's Encrypt certificate notices
3. **Cloudflare API token** — the one you copied in Step 3.2
4. **Timezone** — e.g. `Europe/Kyiv` (this is what n8n schedules run on)

At the end it prints a summary of generated passwords.
**Save them all in your password manager right now.**

**✅ Check:**

```bash
grep -r CHANGE_ME n8n-stack/.env supabase/.env || echo "OK - all secrets set"
```

Must print `OK - all secrets set`.

---

## Step 7 — Start the core stack (Traefik, n8n, Qdrant, Uptime Kuma)

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d
```

The first start downloads ~2 GB of images (2–5 minutes).

**✅ Checks (all four):**

**7.1.** All containers up:

```bash
docker compose ps
```

Every service shows `Up` (give it a minute).

**7.2.** Certificates issued (this can take up to 2 minutes after start):

```bash
docker compose logs traefik | grep -i "certificate" | tail -5
```

No `error` lines. If you see errors, wait 2 minutes and check again —
then see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#certificates).

**7.3.** Open `https://n8n.YOUR_DOMAIN` in a browser. You should see the n8n
**"Set up owner account"** page. Create your account — this login IS the
security of your n8n, use a strong password.

**7.4.** Open `https://uptime.YOUR_DOMAIN` — Uptime Kuma asks you to create an
admin account. Create it.

Qdrant check (from the server; it answers only with the API key):

```bash
source .env && curl -s -H "api-key: $QDRANT_API_KEY" https://qdrant.$BASE_DOMAIN/collections
```

Expected reply: `{"result":{"collections":[]},"status":"ok",...}`

---

## Step 8 — Start Supabase

```bash
cd /root/enterprise-automation-platform/supabase && docker compose up -d
```

First boot downloads ~3 GB and initializes the database — takes **2–5 minutes**.
Some containers will restart a few times while Postgres initializes; that's normal.

**✅ Checks:**

**8.1.** Wait, then confirm everything is healthy:

```bash
docker compose ps
```

All 13 services `Up`, most `(healthy)`. If `analytics` or `kong` keep
restarting after 5 minutes → [TROUBLESHOOTING.md](TROUBLESHOOTING.md#supabase).

**8.2.** Open `https://supabase.YOUR_DOMAIN` — a login prompt appears.
Username: `supabase`, password: the `DASHBOARD_PASSWORD` printed in Step 6
(also in `supabase/.env`). You should see Supabase Studio.

---

## Step 9 — Connect n8n to your databases

Inside Docker, services reach each other by **container name**, not by domain.
Use these values when creating credentials in n8n (**Credentials → Add credential**):

**Postgres** (credential type: *Postgres*):

| Field | Value |
|---|---|
| Host | `supabase-db` |
| Database | `postgres` |
| User | `postgres` |
| Password | `POSTGRES_PASSWORD` from `supabase/.env` |
| Port | `5432` |
| SSL | disable |

> Note: in self-hosted Supabase the `postgres` role is **not** a superuser.
> If you ever need to bypass Row Level Security in admin queries, connect as
> user `supabase_admin` (same password).

**Qdrant** (credential type: *QdrantApi*):

| Field | Value |
|---|---|
| Qdrant URL | `http://qdrant:6333` |
| API Key | `QDRANT_API_KEY` from `n8n-stack/.env` |

**Supabase API** (credential type: *Supabase*):

| Field | Value |
|---|---|
| Host | `http://supabase-kong:8000` |
| Service Role Secret | `SERVICE_ROLE_KEY` from `supabase/.env` |

**✅ Check:** each credential has a **Test** button in n8n — all three must turn green.

---

## Step 10 — Backups

Two scripts, installed as nightly cron jobs:

- `enterprise-backup.sh` (02:00) — configs, .env files, **n8n encryption key**
- `data-backup.sh` (02:30) — full Postgres dump + all n8n workflows and credentials

```bash
cd /root/enterprise-automation-platform && bash scripts/install-backups.sh
```

Now run both once by hand to prove they work:

```bash
bash scripts/enterprise-backup.sh && bash scripts/data-backup.sh
```

**✅ Check:**

```bash
ls -lh /root/backups/daily /root/backups/data
```

You should see a `stack-backup-*.tar.gz`, a `supabase-pgdumpall-*.sql.gz` and
an `n8n-export-*.tar.gz`, all with today's date and non-zero sizes.

**Strongly recommended:** these backups live on the same disk as the server.
Enable your provider's **off-disk** snapshots — Hetzner: server → **Backups**
tab → **Enable Backups** (~20% of server price, 7 daily snapshots);
DigitalOcean: **Backups**; Vultr: **Auto Backups**; AWS: EBS snapshots.
More: [BACKUP_AND_RESTORE.md](BACKUP_AND_RESTORE.md).

---

## Step 11 — Final checklist

| Check | Expected |
|---|---|
| `https://n8n.YOUR_DOMAIN` | n8n login page, padlock icon (valid HTTPS) |
| `https://supabase.YOUR_DOMAIN` | Studio behind basic-auth |
| `https://uptime.YOUR_DOMAIN` | Uptime Kuma dashboard |
| `curl` to qdrant with API key (Step 7.4) | `"status":"ok"` |
| `docker ps` on server | 17 containers, all `Up` |
| `ls /root/backups/data` | today's backup files |
| Provider snapshots/backups | Enabled |

**Done.** Your automation platform is live.

Set up your first monitor in Uptime Kuma (HTTP monitor for
`https://n8n.YOUR_DOMAIN`) and build your first workflow in n8n.

If something didn't work → [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

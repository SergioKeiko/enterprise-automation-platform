# Backup & Restore

**The one thing you must understand:** `n8n-stack/data/config.json` contains
the **n8n encryption key**. Every credential n8n exports is encrypted with it.
**A credentials backup without this file is garbage.** Both backup scripts
include it — never exclude it, and keep a copy of it in your password manager.

## What gets backed up

Two cron jobs (installed by `scripts/install-backups.sh`):

| Script | When | What | Where |
|---|---|---|---|
| `enterprise-backup.sh` | 02:00 | compose files, both `.env`, traefik config, **n8n encryption key** | `/root/backups/configs` + `/root/backups/daily` |
| `data-backup.sh` | 02:30 | full Postgres dump (`pg_dumpall`), all n8n workflows + credentials (encrypted) | `/root/backups/data` |

Retention: 3 days of data dumps, 7 days of configs, 3 daily tarballs.

**Not** covered: Qdrant vectors (usually re-buildable from source data),
Uptime Kuma history, Supabase Storage files. If any of those matter to you,
add them to `data-backup.sh`.

## The off-disk layer (do not skip)

Everything above lands on the **same disk** as the server. A dead disk or a
deleted server takes the backups with it. Two options, use at least one:

1. **Provider snapshots** (easiest): Hetzner — server → **Backups** tab →
   Enable (~20% of server price, 7 daily snapshots); DigitalOcean — **Backups**;
   Vultr — **Auto Backups**; AWS — EBS snapshots. Whole-machine copies,
   stored off your server's disk.
2. **Copy to your computer** (free): run from your computer, e.g. weekly:

```bash
rsync -avz -e "ssh -i ~/.ssh/automation-server" root@YOUR_SERVER_IP:/root/backups/ ~/automation-backups/
```

## Restore runbook (fresh server, total loss scenario)

Assumes you have the contents of `/root/backups` (or a provider snapshot — in
that case just restore the snapshot in your provider's console and you're done).

**1.** Build a new empty server: follow [INSTALL.md](INSTALL.md) steps 1–5
(server, firewall, DNS → new IP, Docker, clone).

**2.** Restore configs instead of generating new secrets (skip step 6!):

```bash
cd /root/enterprise-automation-platform
tar -xzf /path/to/stack-backup-XXXX.tar.gz -C /tmp/restore
cp /tmp/restore/n8n-stack.env  n8n-stack/.env
cp /tmp/restore/supabase.env   supabase/.env
cp -r /tmp/restore/traefik/*   n8n-stack/traefik/
mkdir -p n8n-stack/data
cp /tmp/restore/data/config.json n8n-stack/data/   # the encryption key!
chmod 600 n8n-stack/.env supabase/.env n8n-stack/traefik/acme.json
```

**3.** Start both stacks (INSTALL steps 7 and 8):

```bash
cd n8n-stack  && docker compose up -d && cd ../supabase && docker compose up -d
```

Wait until `docker compose ps` shows everything healthy.

**4.** Restore the Supabase database:

```bash
gunzip -c /path/to/supabase-pgdumpall-XXXX.sql.gz | docker exec -i supabase-db psql -U postgres
```

(Expect a stream of SQL output; occasional "already exists" notices are fine.)

**5.** Restore n8n workflows and credentials:

```bash
mkdir -p n8n-stack/data/import && tar -xzf /path/to/n8n-export-XXXX.tar.gz -C n8n-stack/data/import
docker exec n8n n8n import:workflow --separate --input=/home/node/.n8n/import/workflows/
docker exec n8n n8n import:credentials --separate --input=/home/node/.n8n/import/credentials/
docker compose -f n8n-stack/docker-compose.yml restart n8n
```

**6.** Verify: log in to `https://n8n.YOUR_DOMAIN` — your workflows are there,
open one credential and press **Test**. Check Studio at
`https://supabase.YOUR_DOMAIN` shows your tables.

**7.** Re-activate your workflows (imports arrive deactivated) and re-enable
backups: `bash scripts/install-backups.sh`.

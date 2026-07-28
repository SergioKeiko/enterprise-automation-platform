# Enterprise Automation Platform

A production-tested, self-hosted automation stack. One €16/month server gives you:

| Service | What it does | Your URL |
|---|---|---|
| **n8n** | Workflow automation (the heart of the stack) | `https://n8n.your-domain.com` |
| **Supabase** | Postgres database + Auth + REST API + Storage + Studio UI | `https://supabase.your-domain.com` |
| **Qdrant** | Vector database for AI / RAG workflows | `https://qdrant.your-domain.com` |
| **Uptime Kuma** | Monitoring with alerts | `https://uptime.your-domain.com` |
| **Traefik** | Reverse proxy with automatic free HTTPS certificates | — |

Everything runs in Docker behind Traefik with Let's Encrypt certificates
(issued via Cloudflare DNS), protected by your provider's cloud firewall.
Works on **any VPS provider** — Hetzner, DigitalOcean, Vultr, Contabo, AWS…

This is not a demo — it is a copy of a real production setup that runs
hundreds of workflows daily, with the sharp edges already filed off:
pinned image versions, execution-history pruning, working backup scripts,
and a one-command secrets generator.

## Architecture

```
                 Internet
                    │
              Cloudflare (DNS + proxy)
                    │
        Provider firewall (22/80/443)
                    │
              ┌─── Traefik ───┐  ← automatic HTTPS
              │       │       │
        ┌─────┴──┐ ┌──┴───┐ ┌─┴──────────┐
        │  n8n   │ │Qdrant│ │Uptime Kuma │
        └───┬────┘ └──────┘ └────────────┘
            │  internal docker network "proxy"
        ┌───┴──────────────────────────────┐
        │      Supabase (13 containers)    │
        │  Kong · Postgres · Auth · REST   │
        │  Realtime · Storage · Studio ... │
        └──────────────────────────────────┘
```

## Get started

**→ [INSTALL.md](INSTALL.md)** — full step-by-step guide from zero to a
working stack (~1.5 hours, no DevOps experience required).
Українська версія: **[docs/uk/INSTALL.md](docs/uk/INSTALL.md)**.

Other guides:

- [BACKUP_AND_RESTORE.md](BACKUP_AND_RESTORE.md) — what gets backed up and how to restore
- [UPDATING.md](UPDATING.md) — how to update service versions safely
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — fixes for the most common problems

## Repository layout

```
n8n-stack/          n8n + Traefik + Qdrant + Uptime Kuma (compose project 1)
supabase/           self-hosted Supabase, pinned versions  (compose project 2)
scripts/            secrets generator + backup scripts + cron installer
```

## Requirements

- A server at **any VPS provider** (Hetzner, DigitalOcean, Vultr, Contabo,
  OVH, AWS…): Ubuntu newest LTS, x86, 2+ vCPU, 8 GB RAM recommended
  (4 GB minimum) — e.g. Hetzner CPX31 at ~€16/mo. The install guide shows
  Hetzner screens; every step has an equivalent at any provider.
- A domain with DNS managed by [Cloudflare](https://cloudflare.com) (free plan)
- A terminal on your computer (macOS/Linux Terminal, or Windows Terminal with WSL)

## Optional add-ons

<details>
<summary>Watchtower (automatic container updates)</summary>

This template pins exact versions on purpose — automatic updates can break a
production stack overnight (see [UPDATING.md](UPDATING.md)). If you still want
auto-updates, add this service to `n8n-stack/docker-compose.yml`:

```yaml
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --schedule "0 0 * * *" --cleanup
    environment:
      # Required: watchtower's default Docker API version is too old
      # for modern Docker engines
      - DOCKER_API_VERSION=1.44
```
</details>

<details>
<summary>Redis (for n8n queue mode)</summary>

Single-instance n8n does not need Redis. If you later scale to
[queue mode](https://docs.n8n.io/hosting/scaling/queue-mode/), add:

```yaml
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    volumes:
      - ./redis_data:/data
```
</details>

## License

MIT. The `supabase/` directory is derived from
[supabase/supabase](https://github.com/supabase/supabase) (Apache-2.0) —
see [LICENSE](LICENSE) for details.

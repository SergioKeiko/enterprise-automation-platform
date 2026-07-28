# Troubleshooting

> 🇺🇦 [Українська версія](docs/uk/TROUBLESHOOTING.md)

Every fix below assumes you are logged in to the server:
`ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP`

The single most useful debugging command — logs of any container:

```bash
docker logs --tail 50 <container-name>     # e.g. traefik, n8n, supabase-db
```

---

## <a name="certificates"></a>HTTPS certificate is not issued (browser shows a warning)

**Symptom:** `https://n8n.YOUR_DOMAIN` shows "connection not private" or a
Traefik default certificate.

**Check the Traefik logs:**

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose logs traefik | grep -iE "acme|error" | tail -20
```

Fixes, in order of likelihood:

1. **Wrong or under-scoped Cloudflare token.** The token must have permission
   **Zone → DNS → Edit** for your zone. Recreate it (INSTALL step 3.2), put the
   new value in `n8n-stack/.env` (`CF_DNS_API_TOKEN=...`), then:
   `docker compose up -d traefik`
2. **acme.json has wrong permissions.** Traefik logs say so explicitly. Fix:
   `chmod 600 traefik/acme.json && docker compose restart traefik`
3. **DNS record missing.** `nslookup qdrant.YOUR_DOMAIN` must resolve. Add the
   missing A-record (INSTALL step 3.1) and wait 2 minutes.
4. **Rate limit.** Let's Encrypt allows 5 failures per hour. If logs mention
   `rateLimited`, wait an hour before retrying.

---

## 502 Bad Gateway on one service

**Symptom:** the URL opens with a valid certificate, but shows "Bad Gateway".

Traefik can't reach the container. Almost always a network problem:

```bash
docker inspect <container> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

The output must include `proxy`. If it doesn't:

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d
```

(or the `supabase` directory if it's the Supabase URL failing). If it persists,
check the container itself is running: `docker ps | grep <name>`.

---

## Cloudflare error 521 / 522

**Symptom:** Cloudflare's own error page instead of your service.

Cloudflare cannot reach your server:

1. Server down? Check your provider's console → server is running.
2. Firewall blocking? Rules for TCP 80 **and** 443 must exist (INSTALL step 2).
3. Traefik down? `docker ps | grep traefik` → if missing:
   `cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d`

---

## <a name="supabase"></a>Supabase containers keep restarting

**Symptom:** `docker compose ps` shows `supabase-analytics` or `supabase-kong`
in `Restarting` state for more than 5 minutes.

The start order is: `db` → `analytics` → everything else. Debug from the bottom:

```bash
cd /root/enterprise-automation-platform/supabase
docker logs --tail 30 supabase-db
docker logs --tail 30 supabase-analytics
```

Common causes:

1. **First boot is just slow.** Postgres initializes for several minutes on
   first start. Give it 5 minutes before touching anything.
2. **You changed .env after the first start.** Database passwords are baked in
   at first initialization. If you *must* change `POSTGRES_PASSWORD` after
   first boot, you have to reset the data (DESTROYS ALL DATA):
   `docker compose down -v && rm -rf volumes/db/data && docker compose up -d`
3. **Low memory.** `free -h` — if `available` is near zero, the server is too
   small. CPX31 (8 GB) fits this stack; smaller servers will struggle.

---

## "port is already allocated"

**Symptom:** `docker compose up -d` fails with
`Bind for 0.0.0.0:80 failed: port is already allocated`.

Something else uses the port:

```bash
ss -tlnp | grep -E ':80|:443'
```

Usually it's a system nginx/apache: `systemctl disable --now nginx` (or
`apache2`), then `docker compose up -d` again.

---

## n8n webhooks show the wrong URL

**Symptom:** a Webhook node displays `http://localhost:5678/...` instead of
your domain.

`WEBHOOK_URL` is derived from `BASE_DOMAIN` in `n8n-stack/.env`. Verify it,
then recreate n8n:

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d n8n
```

---

## Disk is filling up

```bash
df -h /          # overall usage
docker system df # what docker occupies
du -sh /root/backups /root/enterprise-automation-platform/n8n-stack/data
```

Safe cleanups:

```bash
docker system prune -f              # unused images/containers (safe)
```

n8n's database grows with execution history. This template ships with pruning
enabled (14 days / 5000 executions). If one workflow still bloats the DB, open
that workflow's **Settings** in n8n and set
**Save successful production executions → Do not save**.

---

## I changed docker-compose.yml but nothing happened

Compose only applies changes on `up`:

```bash
cd <the directory with the changed file> && docker compose up -d
```

`restart` is NOT enough — it restarts the old configuration.

---

## How do I see the Traefik dashboard?

It's bound to the server's localhost only (on purpose). From your computer:

```bash
ssh -i ~/.ssh/automation-server -L 8080:localhost:8080 root@YOUR_SERVER_IP
```

Then open http://localhost:8080 in your browser while the SSH session is open.

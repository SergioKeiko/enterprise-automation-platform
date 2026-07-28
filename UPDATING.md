# Updating

> 🇺🇦 [Українська версія](docs/uk/UPDATING.md)

This template pins **exact image versions** and has no auto-updater. That is a
feature: an unattended major update of n8n or Postgres can take your production
workflows down overnight. Updates here are a 5-minute manual ritual you do
when *you* choose to.

## Before any update

```bash
cd /root/enterprise-automation-platform
bash scripts/enterprise-backup.sh && bash scripts/data-backup.sh
```

## Updating n8n (most frequent)

1. Check the current release notes: https://github.com/n8n-io/n8n/releases —
   look for breaking changes between your version and the target.
2. Edit `n8n-stack/docker-compose.yml`: change the tag in
   `image: n8nio/n8n:2.31.7` to the new version. Prefer moving one minor
   version at a time for big jumps.
3. Apply:

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose pull n8n && docker compose up -d n8n
```

4. Verify: open n8n in the browser, check the version in Settings, run one
   important workflow manually.

**Rollback:** put the old tag back and `docker compose up -d n8n`.
(n8n migrates its database forward — old versions may refuse a downgraded DB;
that's what the pre-update backup is for.)

## Updating Traefik / Qdrant / Uptime Kuma

Same pattern: bump the tag → `docker compose pull <service>` →
`docker compose up -d <service>` → verify the URL answers.

For Qdrant, check your n8n vector workflows still run after the update.

## Updating Supabase (do this rarely and carefully)

Supabase is 13 coordinated containers — versions are tested **as a set**, so
never bump a single Supabase image alone. To upgrade the set:

1. Look at the current upstream compose:
   https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml
2. Diff its image tags against `supabase/docker-compose.yml` in this repo, and
   read the self-hosting changelog for migration notes.
3. Update all tags together, then:

```bash
cd /root/enterprise-automation-platform/supabase && docker compose pull && docker compose up -d
```

4. Watch `docker compose ps` until everything is healthy, then verify Studio
   and one n8n → Postgres workflow.

If you're not comfortable with this, staying on the pinned set is fine —
it's a production-tested combination.

## Updating Ubuntu

```bash
apt update && apt upgrade -y
```

If it prints `*** System restart required ***`, reboot during a quiet window:

```bash
reboot
```

All containers have `restart: always` and come back on their own (~2 min).
Don't skip reboots for months — kernel security fixes only apply after one.

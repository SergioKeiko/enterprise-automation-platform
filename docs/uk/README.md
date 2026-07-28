# Enterprise Automation Platform

> 🇬🇧 [English version](../../README.md)

Перевірена в продакшені self-hosted automation-платформа. Один сервер за ~€16/міс дає тобі:

| Сервіс | Що робить | Твій URL |
|---|---|---|
| **n8n** | Автоматизація воркфлоу (серце стека) | `https://n8n.your-domain.com` |
| **Supabase** | Postgres + Auth + REST API + Storage + Studio UI | `https://supabase.your-domain.com` |
| **Qdrant** | Векторна база для AI / RAG-воркфлоу | `https://qdrant.your-domain.com` |
| **Uptime Kuma** | Моніторинг з алертами | `https://uptime.your-domain.com` |
| **Traefik** | Reverse proxy з автоматичним безкоштовним HTTPS | — |

Все працює в Docker за Traefik із сертифікатами Let's Encrypt (через
Cloudflare DNS), під захистом firewall твого провайдера.
Працює на **будь-якому VPS** — Hetzner, DigitalOcean, Vultr, Contabo, AWS…

Це не демо — це копія реального продакшен-сетапу, який щодня ганяє сотні
воркфлоу, з уже відшліфованими гострими кутами: запінені версії образів,
автоочистка історії виконань, робочі бекап-скрипти і генератор секретів
однією командою.

## Архітектура

```
                 Інтернет
                    │
              Cloudflare (DNS + proxy)
                    │
        Firewall провайдера (22/80/443)
                    │
              ┌─── Traefik ───┐  ← автоматичний HTTPS
              │       │       │
        ┌─────┴──┐ ┌──┴───┐ ┌─┴──────────┐
        │  n8n   │ │Qdrant│ │Uptime Kuma │
        └───┬────┘ └──────┘ └────────────┘
            │  внутрішня docker-мережа "proxy"
        ┌───┴──────────────────────────────┐
        │      Supabase (13 контейнерів)   │
        │  Kong · Postgres · Auth · REST   │
        │  Realtime · Storage · Studio ... │
        └──────────────────────────────────┘
```

## З чого почати

**→ [INSTALL.md](INSTALL.md)** — повна покрокова інструкція від нуля до
робочого стека (~1.5 години, DevOps-досвід не потрібен).
English version: **[INSTALL.md](../../INSTALL.md)**.

Інші гайди:

- [BACKUP_AND_RESTORE.md](BACKUP_AND_RESTORE.md) — що бекапиться і як відновитись
- [UPDATING.md](UPDATING.md) — як безпечно оновлювати версії сервісів
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — фікси найчастіших проблем

## Структура репозиторію

```
n8n-stack/          n8n + Traefik + Qdrant + Uptime Kuma (compose-проєкт 1)
supabase/           self-hosted Supabase, запінені версії  (compose-проєкт 2)
scripts/            генератор секретів + бекап-скрипти + встановлення cron
```

## Вимоги

- Сервер у **будь-якого VPS-провайдера** (Hetzner, DigitalOcean, Vultr,
  Contabo, OVH, AWS…): Ubuntu найновіша LTS, x86, 2+ vCPU, рекомендовано
  8 GB RAM (мінімум 4 GB) — напр. Hetzner CPX31 за ~€16/міс. Інструкція
  показує екрани Hetzner; у кожного кроку є еквівалент у будь-якого провайдера.
- Домен із DNS на [Cloudflare](https://cloudflare.com) (безкоштовний план)
- Термінал на твоєму комп'ютері (macOS/Linux Terminal або Windows Terminal з WSL)

## Опціональні доповнення

<details>
<summary>Watchtower (автооновлення контейнерів)</summary>

Шаблон навмисно пінить точні версії — автооновлення може зламати продакшен
за одну ніч (див. [UPDATING.md](UPDATING.md)). Якщо все ж хочеш автооновлення,
додай цей сервіс у `n8n-stack/docker-compose.yml`:

```yaml
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --schedule "0 0 * * *" --cleanup
    environment:
      # Обов'язково: дефолтна версія Docker API у watchtower застара
      # для сучасних Docker-движків
      - DOCKER_API_VERSION=1.44
```
</details>

<details>
<summary>Redis (для queue mode n8n)</summary>

Одиночному n8n Redis не потрібен. Якщо пізніше масштабуєшся до
[queue mode](https://docs.n8n.io/hosting/scaling/queue-mode/), додай:

```yaml
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    volumes:
      - ./redis_data:/data
```
</details>

## Ліцензія

MIT. Директорія `supabase/` походить від
[supabase/supabase](https://github.com/supabase/supabase) (Apache-2.0) —
деталі в [LICENSE](../../LICENSE).

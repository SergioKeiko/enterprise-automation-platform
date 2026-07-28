# Бекапи та відновлення

> 🇬🇧 [English version](../../BACKUP_AND_RESTORE.md)

**Головне, що треба зрозуміти:** `n8n-stack/data/config.json` містить
**ключ шифрування n8n**. Кожен креденшел, який n8n експортує, зашифрований
саме ним. **Бекап кредів без цього файлу — сміття.** Обидва бекап-скрипти
його включають — ніколи не виключай його і тримай копію в менеджері паролів.

## Що бекапиться

Два cron-завдання (ставляться скриптом `scripts/install-backups.sh`):

| Скрипт | Коли | Що | Куди |
|---|---|---|---|
| `enterprise-backup.sh` | 02:00 | compose-файли, обидва `.env`, конфіг traefik, **ключ шифрування n8n** | `/root/backups/configs` + `/root/backups/daily` |
| `data-backup.sh` | 02:30 | повний дамп Postgres (`pg_dumpall`), всі воркфлоу + креди n8n (зашифровані) | `/root/backups/data` |

Ротація: 3 дні дампів даних, 7 днів конфігів, 3 щоденні tar-архіви.

**НЕ** покривається: вектори Qdrant (зазвичай перебудовуються з вихідних
даних), історія Uptime Kuma, файли Supabase Storage. Якщо щось із цього тобі
важливе — додай у `data-backup.sh`.

## Зовнішній шар (не пропускай)

Все вище лягає на **той самий диск**, що й сервер. Мертвий диск або видалений
сервер забирає бекапи з собою. Два варіанти, використовуй хоча б один:

1. **Снапшоти провайдера** (найпростіше): Hetzner — сервер → вкладка
   **Backups** → Enable (~20% ціни сервера, 7 щоденних снапшотів);
   DigitalOcean — **Backups**; Vultr — **Auto Backups**; AWS — снапшоти EBS.
   Копії всієї машини, зберігаються поза диском сервера.
2. **Копія на твій компʼютер** (безкоштовно): запускай зі свого компʼютера,
   наприклад щотижня:

```bash
rsync -avz -e "ssh -i ~/.ssh/automation-server" root@YOUR_SERVER_IP:/root/backups/ ~/automation-backups/
```

## Ранбук відновлення (свіжий сервер, повна втрата)

Передбачає, що в тебе є вміст `/root/backups` (або снапшот провайдера — тоді
просто віднови снапшот у консолі провайдера, і все).

**1.** Підніми новий порожній сервер: [INSTALL.md](INSTALL.md), кроки 1–5
(сервер, firewall, DNS → новий IP, Docker, клонування).

**2.** Віднови конфіги замість генерації нових секретів (пропусти крок 6!):

```bash
cd /root/enterprise-automation-platform
tar -xzf /path/to/stack-backup-XXXX.tar.gz -C /tmp/restore
cp /tmp/restore/n8n-stack.env  n8n-stack/.env
cp /tmp/restore/supabase.env   supabase/.env
cp -r /tmp/restore/traefik/*   n8n-stack/traefik/
mkdir -p n8n-stack/data
cp /tmp/restore/data/config.json n8n-stack/data/   # ключ шифрування!
chmod 600 n8n-stack/.env supabase/.env n8n-stack/traefik/acme.json
```

**3.** Запусти обидва стеки (INSTALL, кроки 7 і 8):

```bash
cd n8n-stack  && docker compose up -d && cd ../supabase && docker compose up -d
```

Дочекайся, поки `docker compose ps` покаже все healthy.

**4.** Віднови базу Supabase:

```bash
gunzip -c /path/to/supabase-pgdumpall-XXXX.sql.gz | docker exec -i supabase-db psql -U postgres
```

(Очікуй потік SQL-виводу; поодинокі «already exists» — це нормально.)

**5.** Віднови воркфлоу і креди n8n:

```bash
mkdir -p n8n-stack/data/import && tar -xzf /path/to/n8n-export-XXXX.tar.gz -C n8n-stack/data/import
docker exec n8n n8n import:workflow --separate --input=/home/node/.n8n/import/workflows/
docker exec n8n n8n import:credentials --separate --input=/home/node/.n8n/import/credentials/
docker compose -f n8n-stack/docker-compose.yml restart n8n
```

**6.** Перевір: зайди на `https://n8n.YOUR_DOMAIN` — воркфлоу на місці,
відкрий один креденшел і натисни **Test**. Перевір, що Studio на
`https://supabase.YOUR_DOMAIN` показує твої таблиці.

**7.** Реактивуй воркфлоу (імпорт приходить деактивованим) і знову увімкни
бекапи: `bash scripts/install-backups.sh`.

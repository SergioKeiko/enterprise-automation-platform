# Інструкція встановлення

Ця інструкція проведе тебе від **нуля** до **повністю робочої automation-платформи**
приблизно за 1.5 години. Кожен крок каже, що саме ввести або клікнути, і як
перевірити, що все спрацювало, перш ніж іти далі.

**Що потрібно:**

- **Будь-який VPS-провайдер** — Hetzner, DigitalOcean, Vultr, Contabo, OVH, AWS…
  Стеку потрібен лише сервер з **Ubuntu (найновіша LTS), 2+ vCPU, 8 GB RAM
  (мінімум 4 GB), x86**. Інструкція показує екрани Hetzner (~€16/міс там);
  на іншому провайдері роби еквівалентні кліки — поняття скрізь однакові:
  сервер, SSH-ключ, firewall.
- Домен, DNS якого керується через [Cloudflare](https://dash.cloudflare.com) (безкоштовного плану досить).
  Якщо домен деінде — спершу [перенеси nameserver-и на Cloudflare](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/) (~15 хв).
- Термінал: **macOS/Linux** — вбудований Terminal. **Windows** — встанови
  [WSL](https://learn.microsoft.com/uk-ua/windows/wsl/install) і користуйся терміналом Ubuntu.

> 🇬🇧 English version: [../../INSTALL.md](../../INSTALL.md)

---

## Крок 1 — SSH-ключ і сервер

SSH-ключ — це спосіб заходити на сервер без пароля.

**1.1.** У терміналі створи ключ (на всі питання просто натискай Enter):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/automation-server
```

**1.2.** Виведи публічний ключ і скопіюй весь рядок:

```bash
cat ~/.ssh/automation-server.pub
```

**1.3.** Додай публічний ключ у провайдера. На Hetzner:
[Console](https://console.hetzner.cloud) → твій проєкт → **Security** (меню
зліва) → **SSH keys** → **Add SSH key** → встав скопійований рядок → назви
`my-laptop` → **Add SSH key**.
*(Інші провайдери: у формі створення сервера завжди є поле "SSH key" — встав
той самий рядок туди.)*

**1.4.** Створи сервер. На Hetzner: **Servers** → **Add server**:

| Налаштування | Значення |
|---|---|
| Location | Nuremberg (або найближчий до тебе) |
| Image | **Ubuntu** — найновіша LTS зі списку (напр. 24.04 чи 26.04) |
| Type | Shared vCPU (x86) → **CPX31** (4 vCPU / 8 GB) |
| SSH key | познач `my-laptop` |
| Name | `automation-server` |

Решту лишай за замовчуванням → **Create & Buy now**.

*(Інші провайдери: обери еквівалент — Ubuntu найновіша LTS, x86, 2+ vCPU,
8 GB RAM — і прикріпи свій SSH-ключ.)*

**1.5.** Скопіюй IP-адресу сервера зі списку (виглядає як `65.108.xx.xx`).
Далі скрізь заміняй `YOUR_SERVER_IP` на неї.

**✅ Перевірка:** ця команда має відкрити промпт `root@automation-server:~#`:

```bash
ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP
```

(На питання про fingerprint введи `yes`. Вийти — `exit`; але лишайся
залогіненим — наступні кроки частково відбуваються на сервері.)

> Деякі провайдери логінять іншим користувачем (AWS: `ubuntu`, інколи
> `debian`/`admin`). Тоді підключайся під тим користувачем і одразу виконай
> `sudo -i` — далі інструкція розрахована на root.

---

## Крок 2 — Firewall

Закриваємо всі порти, крім потрібних. Використовуй firewall **провайдера**
(він фільтрує трафік ще до сервера — надійніше за firewall на самому сервері,
який Docker частково обходить).

**2.1.** На Hetzner: Console → **Firewalls** (меню зліва) → **Create Firewall**.
*(DigitalOcean: Networking → Firewalls. Vultr: Firewall. AWS: Security Groups.
Правила скрізь ті самі.)*

**2.2.** Додай такі **inbound**-правила (source лишай "Any IPv4/IPv6"):

| Протокол | Порт | Навіщо |
|---|---|---|
| TCP | 22 | SSH (ти) |
| TCP | 80 | HTTP (сертифікати) |
| TCP | 443 | HTTPS (усі сервіси) |
| ICMP | — | ping |

**2.3.** Застосуй firewall до сервера (на Hetzner: **Apply to** →
вибери `automation-server` → **Create Firewall**).

> Якщо у провайдера немає cloud firewall — можна продовжити без нього: кожен
> відкритий сервіс цього стека і так вимагає пароль або API-ключ.
>
> Пізніше, якщо зовнішньому застосунку (наприклад, на Vercel) потрібне
> **пряме** підключення до пулера бази Supabase або її API — дозволь також
> TCP 6543 та/або TCP 8000. «Про запас» не відкривай.

**✅ Перевірка:** SSH досі працює (правило 22 діє):

```bash
ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP
```

---

## Крок 3 — Cloudflare: DNS-записи та API-токен

**3.1.** У [Cloudflare Dashboard](https://dash.cloudflare.com) відкрий свій
домен → **DNS** → **Records**. Створи **4 записи** — по одному на сервіс:

| Type | Name | IPv4 address | Proxy status |
|---|---|---|---|
| A | `n8n` | YOUR_SERVER_IP | 🟠 Proxied |
| A | `supabase` | YOUR_SERVER_IP | 🟠 Proxied |
| A | `qdrant` | YOUR_SERVER_IP | 🟠 Proxied |
| A | `uptime` | YOUR_SERVER_IP | 🟠 Proxied |

**3.2.** Створи API-токен (ним Traefik доводить Let's Encrypt, що домен твій):
іконка профілю (праворуч зверху) → **My Profile** → **API Tokens** →
**Create Token** → **Create Custom Token**:

- Token name: `traefik-dns`
- Permissions: **Zone** → **DNS** → **Edit**
- Zone Resources: **Include** → **Specific zone** → твій домен
- **Continue to summary** → **Create Token**

**Скопіюй токен одразу** — Cloudflare показує його лише раз. Вставиш у кроці 6.

**✅ Перевірка:** у терміналі на твоєму комп'ютері:

```bash
nslookup n8n.YOUR_DOMAIN
```

Мають повернутись IP-адреси (Cloudflare-івські, не твого сервера — це
правильно: proxy ховає IP сервера).

---

## Крок 4 — Docker на сервері

Залогінься на сервер (`ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP`)
і виконай:

```bash
apt update && apt upgrade -y
```

```bash
curl -fsSL https://get.docker.com | sh
```

Створи спільну мережу, яка з'єднує Traefik з усіма сервісами:

```bash
docker network create proxy
```

**✅ Перевірка:**

```bash
docker --version && docker compose version && docker network ls | grep proxy
```

Маєш побачити версію Docker, версію Compose і рядок із `proxy`.

---

## Крок 5 — Код

Далі на сервері:

```bash
cd /root && git clone https://github.com/SergioKeiko/enterprise-automation-platform.git
```

```bash
cd /root/enterprise-automation-platform
```

Створи (поки порожній) файл сховища сертифікатів зі строгими правами —
без цього Traefik не стартує:

```bash
touch n8n-stack/traefik/acme.json && chmod 600 n8n-stack/traefik/acme.json
```

Створи папку даних n8n від імені користувача контейнера (n8n працює від
user 1000 всередині контейнера і падає, якщо папка належить root):

```bash
mkdir -p n8n-stack/data && chown 1000:1000 n8n-stack/data
```

**✅ Перевірка:** `ls -a n8n-stack` показує `docker-compose.yml`, `traefik`, `.env.example`.

---

## Крок 6 — Генерація всіх секретів

Один скрипт ставить 4 питання і генерує всі паролі та ключі (їх 10+ —
руками цього не роби):

```bash
bash scripts/generate-secrets.sh
```

Він спитає:

1. **Базовий домен** — напр. `example.com` (без `https://`, без субдомена)
2. **E-mail** — тільки для повідомлень Let's Encrypt про сертифікати
3. **Cloudflare API token** — той, що скопіював у кроці 3.2
4. **Часовий пояс** — напр. `Europe/Kyiv` (за ним працюють розклади n8n)

Наприкінці скрипт виведе згенеровані паролі.
**Одразу збережи їх у менеджер паролів.**

**✅ Перевірка:**

```bash
grep -r CHANGE_ME n8n-stack/.env supabase/.env || echo "OK - all secrets set"
```

Має надрукувати `OK - all secrets set`.

---

## Крок 7 — Старт основного стека (Traefik, n8n, Qdrant, Uptime Kuma)

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d
```

Перший старт завантажує ~2 GB образів (2–5 хвилин).

**✅ Перевірки (всі чотири):**

**7.1.** Усі контейнери піднялись:

```bash
docker compose ps
```

Кожен сервіс у стані `Up` (дай хвилину).

**7.2.** Сертифікати випущені (може тривати до 2 хвилин після старту):

```bash
docker compose logs traefik | grep -i "certificate" | tail -5
```

Без рядків `error`. Якщо помилки — почекай 2 хвилини і перевір ще раз, потім
дивись [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#certificates).

**7.3.** Відкрий у браузері `https://n8n.YOUR_DOMAIN` — має бути сторінка n8n
**"Set up owner account"**. Створи акаунт — цей логін і Є захистом твого n8n,
використовуй сильний пароль.

**7.4.** Відкрий `https://uptime.YOUR_DOMAIN` — Uptime Kuma запропонує
створити адмін-акаунт. Створи.

Перевірка Qdrant (із сервера; він відповідає тільки з API-ключем):

```bash
source .env && curl -s -H "api-key: $QDRANT_API_KEY" https://qdrant.$BASE_DOMAIN/collections
```

Очікувана відповідь: `{"result":{"collections":[]},"status":"ok",...}`

---

## Крок 8 — Старт Supabase

```bash
cd /root/enterprise-automation-platform/supabase && docker compose up -d
```

Перший бут завантажує ~3 GB і ініціалізує базу — **2–5 хвилин**. Деякі
контейнери кілька разів перезапустяться, поки ініціалізується Postgres — це
нормально.

**✅ Перевірки:**

**8.1.** Почекай, потім переконайся, що все healthy:

```bash
docker compose ps
```

Усі 13 сервісів `Up`, більшість `(healthy)`. Якщо `analytics` чи `kong`
перезапускаються довше 5 хвилин → [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#supabase).

**8.2.** Відкрий `https://supabase.YOUR_DOMAIN` — з'явиться вікно логіну.
Username: `supabase`, пароль: `DASHBOARD_PASSWORD` з кроку 6 (він же у
`supabase/.env`). Маєш побачити Supabase Studio.

---

## Крок 9 — Підключення n8n до баз

Всередині Docker сервіси звертаються один до одного за **іменем контейнера**,
не за доменом. Використовуй ці значення у кредах n8n
(**Credentials → Add credential**):

**Postgres** (тип креденшела: *Postgres*):

| Поле | Значення |
|---|---|
| Host | `supabase-db` |
| Database | `postgres` |
| User | `postgres` |
| Password | `POSTGRES_PASSWORD` із `supabase/.env` |
| Port | `5432` |
| SSL | disable |

> Нюанс: у self-hosted Supabase роль `postgres` — **не** суперюзер. Якщо
> колись треба обійти Row Level Security в адмін-запитах — підключайся
> користувачем `supabase_admin` (пароль той самий).

**Qdrant** (тип: *QdrantApi*):

| Поле | Значення |
|---|---|
| Qdrant URL | `http://qdrant:6333` |
| API Key | `QDRANT_API_KEY` із `n8n-stack/.env` |

**Supabase API** (тип: *Supabase*):

| Поле | Значення |
|---|---|
| Host | `http://supabase-kong:8000` |
| Service Role Secret | `SERVICE_ROLE_KEY` із `supabase/.env` |

**✅ Перевірка:** у кожного креденшела в n8n є кнопка **Test** — усі три мають
стати зеленими.

---

## Крок 10 — Бекапи

Два скрипти, які ставляться в нічний cron:

- `enterprise-backup.sh` (02:00) — конфіги, .env-файли, **ключ шифрування n8n**
- `data-backup.sh` (02:30) — повний дамп Postgres + усі воркфлоу і креди n8n

```bash
cd /root/enterprise-automation-platform && bash scripts/install-backups.sh
```

Тепер прожени обидва вручну, щоб довести, що вони працюють:

```bash
bash scripts/enterprise-backup.sh && bash scripts/data-backup.sh
```

**✅ Перевірка:**

```bash
ls -lh /root/backups/daily /root/backups/data
```

Мають бути `stack-backup-*.tar.gz`, `supabase-pgdumpall-*.sql.gz` і
`n8n-export-*.tar.gz` — із сьогоднішньою датою і ненульовими розмірами.

**Дуже рекомендовано:** ці бекапи лежать на тому ж диску, що й сервер. Увімкни
**зовнішні** снапшоти провайдера — Hetzner: сервер → вкладка **Backups** →
**Enable Backups** (~20% ціни сервера, 7 щоденних снапшотів); DigitalOcean:
**Backups**; Vultr: **Auto Backups**; AWS: снапшоти EBS.
Детальніше: [BACKUP_AND_RESTORE.md](../../BACKUP_AND_RESTORE.md).

---

## Крок 11 — Фінальний чекліст

| Перевірка | Очікуваний результат |
|---|---|
| `https://n8n.YOUR_DOMAIN` | сторінка логіну n8n, замочок (валідний HTTPS) |
| `https://supabase.YOUR_DOMAIN` | Studio за basic-auth |
| `https://uptime.YOUR_DOMAIN` | дашборд Uptime Kuma |
| `curl` до qdrant з API-ключем (крок 7.4) | `"status":"ok"` |
| `docker ps` на сервері | 17 контейнерів, усі `Up` |
| `ls /root/backups/data` | сьогоднішні файли бекапів |
| Снапшоти/бекапи провайдера | Enabled |

**Готово.** Твоя automation-платформа працює.

Постав перший монітор в Uptime Kuma (HTTP-монітор на
`https://n8n.YOUR_DOMAIN`) і збери перший воркфлоу в n8n.

Щось не спрацювало → [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md).

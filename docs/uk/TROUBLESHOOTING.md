# Вирішення проблем

> 🇬🇧 [English version](../../TROUBLESHOOTING.md)

Кожен фікс нижче передбачає, що ти залогінений на сервер:
`ssh -i ~/.ssh/automation-server root@YOUR_SERVER_IP`

Найкорисніша команда для дебагу — логи будь-якого контейнера:

```bash
docker logs --tail 50 <імʼя-контейнера>     # напр. traefik, n8n, supabase-db
```

---

## <a name="certificates"></a>HTTPS-сертифікат не випускається (браузер свариться)

**Симптом:** `https://n8n.YOUR_DOMAIN` показує «зʼєднання не захищене» або
дефолтний сертифікат Traefik.

**Дивись логи Traefik:**

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose logs traefik | grep -iE "acme|error" | tail -20
```

Фікси за ймовірністю:

1. **Неправильний або обрізаний Cloudflare-токен.** Токен мусить мати право
   **Zone → DNS → Edit** для твоєї зони. Створи заново (INSTALL, крок 3.2),
   встав нове значення у `n8n-stack/.env` (`CF_DNS_API_TOKEN=...`), потім:
   `docker compose up -d traefik`
2. **Неправильні права на acme.json.** Traefik прямо пише це в лог. Фікс:
   `chmod 600 traefik/acme.json && docker compose restart traefik`
3. **Немає DNS-запису.** `nslookup qdrant.YOUR_DOMAIN` мусить резолвитись.
   Додай відсутній A-запис (INSTALL, крок 3.1) і почекай 2 хвилини.
4. **Rate limit.** Let's Encrypt дозволяє 5 невдач на годину. Якщо в логах
   `rateLimited` — почекай годину.

---

## 502 Bad Gateway на одному сервісі

**Симптом:** URL відкривається з валідним сертифікатом, але показує "Bad Gateway".

Traefik не дотягується до контейнера. Майже завжди — мережа:

```bash
docker inspect <контейнер> --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

У виводі мусить бути `proxy`. Якщо немає:

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d
```

(або директорія `supabase`, якщо падає Supabase-URL). Якщо не допомогло —
перевір, що контейнер взагалі живий: `docker ps | grep <імʼя>`.

---

## Помилка Cloudflare 521 / 522

**Симптом:** сторінка помилки самого Cloudflare замість твого сервісу.

Cloudflare не може достукатись до сервера:

1. Сервер лежить? Перевір у консолі провайдера, що він запущений.
2. Firewall блокує? Мають існувати правила для TCP 80 **і** 443 (INSTALL, крок 2).
3. Traefik лежить? `docker ps | grep traefik` → якщо немає:
   `cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d`

---

## <a name="supabase"></a>Контейнери Supabase постійно перезапускаються

**Симптом:** `docker compose ps` показує `supabase-analytics` чи `supabase-kong`
у стані `Restarting` довше 5 хвилин.

Порядок старту: `db` → `analytics` → все інше. Дебаж знизу вгору:

```bash
cd /root/enterprise-automation-platform/supabase
docker logs --tail 30 supabase-db
docker logs --tail 30 supabase-analytics
```

Типові причини:

1. **Перший бут просто повільний.** Postgres ініціалізується кілька хвилин.
   Дай йому 5 хвилин, перш ніж щось чіпати.
2. **Ти змінив .env після першого старту.** Паролі бази запікаються при першій
   ініціалізації. Якщо *конче треба* змінити `POSTGRES_PASSWORD` після першого
   буту — доведеться скинути дані (ЗНИЩУЄ ВСІ ДАНІ):
   `docker compose down -v && rm -rf volumes/db/data && docker compose up -d`
3. **Мало памʼяті.** `free -h` — якщо `available` біля нуля, сервер замалий.
   8 GB вміщує цей стек; менші сервери страждатимуть.

---

## "port is already allocated"

**Симптом:** `docker compose up -d` падає з
`Bind for 0.0.0.0:80 failed: port is already allocated`.

Порт зайнятий чимось іншим:

```bash
ss -tlnp | grep -E ':80|:443'
```

Зазвичай це системний nginx/apache: `systemctl disable --now nginx` (або
`apache2`), потім знову `docker compose up -d`.

---

## Вебхуки n8n показують неправильний URL

**Симптом:** Webhook-нода показує `http://localhost:5678/...` замість твого домену.

`WEBHOOK_URL` береться з `BASE_DOMAIN` у `n8n-stack/.env`. Перевір його, потім
перестворити n8n:

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose up -d n8n
```

---

## Диск забивається

```bash
df -h /          # загальне використання
docker system df # скільки займає docker
du -sh /root/backups /root/enterprise-automation-platform/n8n-stack/data
```

Безпечні чистки:

```bash
docker system prune -f              # невикористані образи/контейнери (безпечно)
```

База n8n росте разом з історією виконань. У шаблоні автоочистка вже увімкнена
(14 днів / 5000 виконань). Якщо якийсь один воркфлоу все одно роздуває базу —
відкрий **Settings** цього воркфлоу в n8n і постав
**Save successful production executions → Do not save**.

---

## Я змінив docker-compose.yml, а нічого не сталось

Compose застосовує зміни тільки на `up`:

```bash
cd <директорія зі зміненим файлом> && docker compose up -d
```

`restart` — НЕ достатньо: він перезапускає стару конфігурацію.

---

## Як подивитись дашборд Traefik?

Він навмисно привʼязаний тільки до localhost сервера. З твого компʼютера:

```bash
ssh -i ~/.ssh/automation-server -L 8080:localhost:8080 root@YOUR_SERVER_IP
```

Поки SSH-сесія відкрита — відкрий http://localhost:8080 у браузері.

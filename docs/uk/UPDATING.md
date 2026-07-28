# Оновлення

> 🇬🇧 [English version](../../UPDATING.md)

Цей шаблон пінить **точні версії образів** і не має автооновлювача. Це
фіча: безконтрольне мажорне оновлення n8n чи Postgres може покласти твої
продакшен-воркфлоу за одну ніч. Оновлення тут — 5-хвилинний ручний ритуал,
який ти робиш тоді, коли вирішив *ти*.

## Перед будь-яким оновленням

```bash
cd /root/enterprise-automation-platform
bash scripts/enterprise-backup.sh && bash scripts/data-backup.sh
```

## Оновлення n8n (найчастіше)

1. Подивись release notes: https://github.com/n8n-io/n8n/releases — шукай
   breaking changes між твоєю версією і цільовою.
2. Відредагуй `n8n-stack/docker-compose.yml`: зміни тег у
   `image: n8nio/n8n:2.31.7` на нову версію. Великі стрибки краще робити
   по одній мінорній версії за раз.
3. Застосуй:

```bash
cd /root/enterprise-automation-platform/n8n-stack && docker compose pull n8n && docker compose up -d n8n
```

4. Перевір: відкрий n8n у браузері, глянь версію в Settings, прожени вручну
   один важливий воркфлоу.

**Відкат:** поверни старий тег і `docker compose up -d n8n`.
(n8n мігрує свою базу вперед — стара версія може відмовитись від новішої
бази; саме для цього бекап перед оновленням.)

## Оновлення Traefik / Qdrant / Uptime Kuma

Той самий патерн: підняти тег → `docker compose pull <сервіс>` →
`docker compose up -d <сервіс>` → перевірити, що URL відповідає.

Для Qdrant — перевір, що векторні воркфлоу n8n досі працюють.

## Оновлення Supabase (рідко і обережно)

Supabase — це 13 узгоджених контейнерів, версії тестуються **набором**, тому
ніколи не піднімай один Supabase-образ окремо. Щоб оновити набір:

1. Подивись поточний upstream compose:
   https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml
2. Порівняй теги образів із `supabase/docker-compose.yml` у цьому репо і
   почитай changelog self-hosting щодо міграцій.
3. Онови всі теги разом, потім:

```bash
cd /root/enterprise-automation-platform/supabase && docker compose pull && docker compose up -d
```

4. Спостерігай `docker compose ps`, поки все не стане healthy, потім перевір
   Studio і один воркфлоу n8n → Postgres.

Якщо тобі з цим некомфортно — лишатися на запіненому наборі цілком нормально:
це перевірена в продакшені комбінація.

## Оновлення Ubuntu

```bash
apt update && apt upgrade -y
```

Якщо надрукує `*** System restart required ***` — перезавантаж у спокійне вікно:

```bash
reboot
```

Усі контейнери мають `restart: always` і піднімуться самі (~2 хв).
Не відкладай ребути на місяці — фікси безпеки ядра діють тільки після ребуту.

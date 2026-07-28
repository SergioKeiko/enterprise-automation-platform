#!/usr/bin/env bash
# ============================================================
# generate-secrets.sh — one-shot setup of all secrets and .env files
#
# Run from the repository root:
#   bash scripts/generate-secrets.sh
#
# What it does:
#   1. Asks for your domain, e-mail and Cloudflare API token
#   2. Generates every secret (passwords, JWT keys, tokens)
#   3. Writes n8n-stack/.env and supabase/.env
#   4. Puts your e-mail into the Traefik certificate config
#   5. Prints a summary you should save in a password manager
#
# It never overwrites an existing .env — delete them first if you
# really want to start over.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)

N8N_ENV="$REPO_ROOT/n8n-stack/.env"
SB_ENV="$REPO_ROOT/supabase/.env"
TRAEFIK_YML="$REPO_ROOT/n8n-stack/traefik/traefik.yml"

for f in "$N8N_ENV" "$SB_ENV"; do
  if [ -f "$f" ]; then
    echo "ERROR: $f already exists. Delete it first if you want to regenerate." >&2
    exit 1
  fi
done

# ---------- helpers ----------

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# sign_jwt <role> <secret> — HS256 JWT valid for 10 years
sign_jwt() {
  local role=$1 secret=$2 now exp header payload signature
  now=$(date +%s)
  exp=$((now + 315360000)) # +10 years
  header=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"role":"%s","iss":"supabase","iat":%s,"exp":%s}' "$role" "$now" "$exp" | b64url)
  signature=$(printf '%s.%s' "$header" "$payload" \
    | openssl dgst -sha256 -hmac "$secret" -binary | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

# verify_jwt <jwt> <secret> — self-test that the signature is valid
verify_jwt() {
  local jwt=$1 secret=$2 head_payload sig expect
  head_payload=${jwt%.*}
  sig=${jwt##*.}
  expect=$(printf '%s' "$head_payload" | openssl dgst -sha256 -hmac "$secret" -binary | b64url)
  [ "$sig" = "$expect" ]
}

rand_hex() { openssl rand -hex "$1"; }
rand_alnum() { openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$1"; }

# ---------- questions ----------

echo "=============================================="
echo " Enterprise Automation Platform — secrets setup"
echo "=============================================="
echo
read -rp "Your base domain (e.g. example.com): " BASE_DOMAIN
read -rp "Your e-mail (for Let's Encrypt certificates): " ACME_EMAIL
read -rp "Cloudflare API token (Zone->DNS->Edit): " CF_DNS_API_TOKEN
read -rp "Timezone [Europe/Kyiv]: " GENERIC_TIMEZONE
GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Europe/Kyiv}

[ -n "$BASE_DOMAIN" ] || { echo "Domain must not be empty" >&2; exit 1; }
[ -n "$ACME_EMAIL" ] || { echo "E-mail must not be empty" >&2; exit 1; }
[ -n "$CF_DNS_API_TOKEN" ] || { echo "Cloudflare token must not be empty" >&2; exit 1; }

# ---------- generation ----------

echo
echo "Generating secrets..."

QDRANT_API_KEY=$(rand_hex 32)
POSTGRES_PASSWORD=$(rand_alnum 32)   # alnum only — special chars break connection strings
JWT_SECRET=$(rand_hex 20)            # 40 chars, >= 32 required
ANON_KEY=$(sign_jwt anon "$JWT_SECRET")
SERVICE_ROLE_KEY=$(sign_jwt service_role "$JWT_SECRET")
DASHBOARD_PASSWORD=$(rand_alnum 24)
SECRET_KEY_BASE=$(rand_hex 32)
VAULT_ENC_KEY=$(rand_alnum 32)       # must be exactly 32 chars
LOGFLARE_PUBLIC_ACCESS_TOKEN=$(rand_hex 24)
LOGFLARE_PRIVATE_ACCESS_TOKEN=$(rand_hex 24)

# self-test: verify JWT signatures before writing anything
verify_jwt "$ANON_KEY" "$JWT_SECRET" || { echo "JWT self-test failed (anon)" >&2; exit 1; }
verify_jwt "$SERVICE_ROLE_KEY" "$JWT_SECRET" || { echo "JWT self-test failed (service_role)" >&2; exit 1; }
[ ${#VAULT_ENC_KEY} -eq 32 ] || { echo "VAULT_ENC_KEY length test failed" >&2; exit 1; }
echo "Self-test passed (JWT signatures valid)."

# ---------- write n8n-stack/.env ----------

sed -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=$BASE_DOMAIN|" \
    -e "s|^CF_DNS_API_TOKEN=.*|CF_DNS_API_TOKEN=$CF_DNS_API_TOKEN|" \
    -e "s|^QDRANT_API_KEY=.*|QDRANT_API_KEY=$QDRANT_API_KEY|" \
    -e "s|^GENERIC_TIMEZONE=.*|GENERIC_TIMEZONE=$GENERIC_TIMEZONE|" \
    "$REPO_ROOT/n8n-stack/.env.example" > "$N8N_ENV"
chmod 600 "$N8N_ENV"

# ---------- write supabase/.env ----------

sed -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=$BASE_DOMAIN|" \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" \
    -e "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" \
    -e "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" \
    -e "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|" \
    -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY_BASE|" \
    -e "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$VAULT_ENC_KEY|" \
    -e "s|^LOGFLARE_PUBLIC_ACCESS_TOKEN=.*|LOGFLARE_PUBLIC_ACCESS_TOKEN=$LOGFLARE_PUBLIC_ACCESS_TOKEN|" \
    -e "s|^LOGFLARE_PRIVATE_ACCESS_TOKEN=.*|LOGFLARE_PRIVATE_ACCESS_TOKEN=$LOGFLARE_PRIVATE_ACCESS_TOKEN|" \
    -e "s|^SITE_URL=.*|SITE_URL=https://supabase.$BASE_DOMAIN|" \
    -e "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://supabase.$BASE_DOMAIN|" \
    -e "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://supabase.$BASE_DOMAIN|" \
    -e "s|^SMTP_ADMIN_EMAIL=.*|SMTP_ADMIN_EMAIL=$ACME_EMAIL|" \
    "$REPO_ROOT/supabase/.env.example" > "$SB_ENV"
chmod 600 "$SB_ENV"

# ---------- traefik acme email ----------

sed -i.bak "s|__ACME_EMAIL__|$ACME_EMAIL|" "$TRAEFIK_YML" && rm -f "$TRAEFIK_YML.bak"

# ---------- sanity check ----------

if grep -q "=CHANGE_ME" "$N8N_ENV" "$SB_ENV"; then
  echo "ERROR: CHANGE_ME markers remain — something went wrong." >&2
  exit 1
fi

# ---------- summary ----------

echo
echo "=============================================="
echo " Done. Save these in your password manager NOW:"
echo "=============================================="
echo "Supabase Studio login:    supabase / $DASHBOARD_PASSWORD"
echo "Postgres password:        $POSTGRES_PASSWORD"
echo "Qdrant API key:           $QDRANT_API_KEY"
echo "Supabase anon key:        $ANON_KEY"
echo "Supabase service key:     $SERVICE_ROLE_KEY"
echo
echo "Files written:"
echo "  n8n-stack/.env"
echo "  supabase/.env"
echo "  n8n-stack/traefik/traefik.yml (certificate e-mail)"
echo
echo "Next step: INSTALL.md — step 7 (start the n8n stack)."

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

set -a
# shellcheck disable=SC1091
source .env
set +a

if [ "$#" -gt 0 ]; then
  DOMAINS=("$@")
else
  DOMAINS=("${S3_DOMAIN:?S3_DOMAIN is required in .env}" "${CONSOLE_DOMAIN:?CONSOLE_DOMAIN is required in .env}")
fi

EMAIL=${EMAIL:?EMAIL is required in .env}

issue_cert() {
  local domain="$1"
  docker compose run --rm --name "vps-certbot-init" --entrypoint certbot certbot \
    certonly --webroot --webroot-path /var/www/certbot \
    --email "$EMAIL" --agree-tos --no-eff-email \
    --force-renewal \
    -d "$domain"
}

for domain in "${DOMAINS[@]}"; do
  echo "=== Issuing certificate for ${domain} ==="
  issue_cert "$domain"
done

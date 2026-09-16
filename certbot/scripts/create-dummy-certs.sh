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

docker volume create vps-infra-certbot-conf >/dev/null

for domain in "${DOMAINS[@]}"; do
  docker run --rm \
    -v vps-infra-certbot-conf:/etc/letsencrypt \
    -e DOMAIN="${domain}" \
    alpine:3.20 sh -c '
      apk add --no-cache openssl >/dev/null
      dir="/etc/letsencrypt/live/${DOMAIN}"
      if [ ! -f "${dir}/fullchain.pem" ]; then
        mkdir -p "$dir"
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
          -keyout "${dir}/privkey.pem" \
          -out "${dir}/fullchain.pem" \
          -subj "/CN=${DOMAIN}" >/dev/null 2>&1
        cp "${dir}/fullchain.pem" "${dir}/cert.pem"
        cp "${dir}/fullchain.pem" "${dir}/chain.pem"
        echo "Dummy certificate created for ${DOMAIN}"
      else
        echo "Certificate already exists for ${DOMAIN}, skipping"
      fi
    '
done

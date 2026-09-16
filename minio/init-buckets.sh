#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

set -a
# shellcheck disable=SC1091
source .env
set +a

MINIO_ROOT_USER=${MINIO_ROOT_USER:?MINIO_ROOT_USER is required in .env}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required in .env}

run_mc() {
  docker run --rm --network vps-infra-internal \
    -v "${REPO_ROOT}/minio/policies:/policies:ro" \
    --entrypoint /bin/sh \
    quay.io/minio/mc:latest \
    -c "mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' >/dev/null && $*"
}

echo "=== Creating buckets ==="
run_mc "mc mb local/odd-oddities-dev --ignore-existing"
run_mc "mc mb local/odd-oddities-prod --ignore-existing"

echo "=== Creating IAM policies ==="
run_mc "mc admin policy create local odd-oddities-dev /policies/odd-oddities-dev.json || true"
run_mc "mc admin policy create local odd-oddities-prod /policies/odd-oddities-prod.json || true"

echo ""
echo "=== Buckets ==="
run_mc "mc ls local"

echo ""
echo "Quota is enforced by the Odd Oddities worker (BR-009), not by MinIO."
echo ""
echo "Next steps — create service accounts in the Console:"
echo "1. Open https://minio-console.binaryten.com.br"
echo "2. Nginx basic auth (user from security/.htpasswd), then MinIO root login"
echo "3. Access Keys > Create access key"
echo "4. Restrict each key to policy odd-oddities-dev or odd-oddities-prod"
echo "5. Save Access Key and Secret Key in the project .env"

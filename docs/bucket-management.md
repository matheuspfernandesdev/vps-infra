# Gerenciamento de Buckets

Como criar e gerenciar buckets no MinIO compartilhado.

MinIO nao esta exposto na internet. Porta 9000 escuta so em `127.0.0.1` na VPS. De outro computador, use SSH ou a rede Docker `vps-infra-internal`.

---

## Pre-requisitos

- `vps-infra` no ar (`docker compose ps` com minio healthy)
- SSH na VPS, pasta `/opt/vps-infra`
- `.env` com `MINIO_ROOT_USER` e `MINIO_ROOT_PASSWORD`

Helper (rode na VPS):

```bash
cd /opt/vps-infra
set -a && source .env && set +a

run_mc() {
  docker run --rm --network vps-infra-internal \
    --entrypoint /bin/sh quay.io/minio/mc:latest \
    -c "mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' >/dev/null && $*"
}
```

---

## Criar bucket para um projeto novo

Padrao de nome: `<projeto>-dev` e `<projeto>-prod`.

```bash
run_mc "mc mb local/meu-projeto-dev --ignore-existing"
run_mc "mc mb local/meu-projeto-prod --ignore-existing"
```

---

## Policy IAM (um bucket)

Crie `/opt/vps-infra/minio/policies/meu-projeto-dev.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::meu-projeto-dev",
        "arn:aws:s3:::meu-projeto-dev/*"
      ]
    }
  ]
}
```

```bash
docker run --rm --network vps-infra-internal \
  -v /opt/vps-infra/minio/policies:/policies:ro \
  --entrypoint /bin/sh quay.io/minio/mc:latest \
  -c "mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' >/dev/null && mc admin policy create local meu-projeto-dev /policies/meu-projeto-dev.json"
```

---

## Access Key no Console

1. `https://minio-console.binaryten.com.br`
2. Basic auth Nginx + login root MinIO
3. **Access Keys** → **Create access key**
4. Anexe a policy do bucket (`meu-projeto-dev` ou `meu-projeto-prod`)
5. Guarde Access Key e Secret Key

Nao use o usuario root nos projetos.

---

## Comandos uteis

```bash
run_mc "mc ls local"
run_mc "mc ls local/odd-oddities-dev"
run_mc "mc du local/odd-oddities-dev"
run_mc "mc admin policy list local"
run_mc "mc rm local/odd-oddities-dev/caminho/do/objeto"
```

Remover bucket (irreversivel):

```bash
run_mc "mc rb local/nome-do-bucket --force"
```

---

## Integrar com o projeto

```env
MINIO_ACCESS_KEY=<access-key>
MINIO_SECRET_KEY=<secret-key>
MINIO_BUCKET_NAME=<nome-do-bucket>
STORAGE_DOMAIN=s3.binaryten.com.br
```

Endpoint publico (todos os projetos): `https://s3.binaryten.com.br`

Path-style: `https://s3.binaryten.com.br/<bucket>/<objeto>`

---

## Nomenclatura

```
odd-oddities-dev
odd-oddities-prod
<projeto>-dev
<projeto>-prod
```

# VPS Infra — MinIO + Nginx + CertBot

Infraestrutura compartilhada de object storage (S3) com TLS. Repositorio separado dos projetos de aplicacao.

**Antes de subir na VPS, leia:** [docs/setup-guide.md](./docs/setup-guide.md)

---

## Visao geral

| Componente | Funcao |
|---|---|
| MinIO | Object storage S3-compativel (buckets privados) |
| Nginx | Reverse proxy HTTPS (API S3 + Console) |
| Certbot | Let's Encrypt (emissao e renovacao via scripts, nao fica rodando) |

| URL | Uso |
|---|---|
| `https://s3.binaryten.com.br` | API S3 (path-style) |
| `https://minio-console.binaryten.com.br` | Console (login MinIO) |

Buckets iniciais: `odd-oddities-dev`, `odd-oddities-prod`

---

## Estrutura

```
vps-infra/
├── docs/
│   ├── setup-guide.md
│   ├── hostinger-dns.md
│   └── bucket-management.md
├── docker-compose.yml
├── .env.example
├── nginx/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── templates/
│       ├── minio.conf.template
│       └── minio-console.conf.template
├── certbot/scripts/
│   ├── create-dummy-certs.sh
│   ├── init-cert.sh
│   └── renew.sh
├── minio/
│   ├── init-buckets.sh
│   └── policies/
└── security/
    └── .htpasswd.example
```

---

## Ordem de execucao (resumo)

O detalhe esta no [setup-guide.md](./docs/setup-guide.md). Nao pule o passo dos certificados dummy.

```bash
# Na VPS, em /opt/vps-infra
cp .env.example .env && nano .env

sed -i 's/\r$//' certbot/scripts/*.sh minio/*.sh
chmod +x certbot/scripts/*.sh minio/init-buckets.sh

bash certbot/scripts/create-dummy-certs.sh
docker compose up -d minio nginx
bash certbot/scripts/init-cert.sh
docker compose exec nginx nginx -s reload
bash minio/init-buckets.sh
```

---

## Documentacao

| Arquivo | Conteudo |
|---|---|
| [setup-guide.md](./docs/setup-guide.md) | Runbook completo (VPS, DNS, deploy, buckets, cron) |
| [add-new-service.md](./docs/add-new-service.md) | Publicar um novo servico (API/MVC) com HTTPS |
| [hostinger-dns.md](./docs/hostinger-dns.md) | Registros A na Hostinger |
| [bucket-management.md](./docs/bucket-management.md) | Novos buckets e access keys |

---

## Seguranca

- Buckets privados; a Meta acessa so via URL pre-assinada
- API S3 publica so na 443; portas 9000/9001 so em `127.0.0.1`
- Console com login MinIO (auth nativo)
- `.env` fora do Git
- Access keys por projeto/bucket, nunca o root nos apps

# Adicionando um Novo Servico na VPS

Como publicar um novo sistema (API .NET, MVC, etc.) com HTTPS nesta infraestrutura.

O `setup-guide.md` configura o MinIO (um caso especifico). Este documento descreve o **procedimento generico** para qualquer dominio novo, ex: `api.binaryten.com.br`.

---

## O que e automatico e o que nao e

| Acao | Automatica? |
|---|---|
| **Renovacao** de certificados existentes (via cron + `renew.sh`) | Sim — o Certbot renova todos |
| **Emissao** de certificado para um dominio novo | Nao — precisa rodar `init-cert.sh` uma vez |
| **Detectar** um novo servico/vhost automaticamente | Nao — o vhost deve ser criado a mao |

Cada servico novo exige 3 passos: **DNS**, **vhost**, **certificado**.

---

## Passo 1 — DNS na Hostinger

Criar um registro `A` apontando para o IP da VPS (mesmo processo de [hostinger-dns.md](./hostinger-dns.md)):

| Tipo | Nome | Aponta para | TTL |
|---|---|---|---|
| `A` | `api` | IP da VPS | `300` |

Confirmar propagacao (na maquina local):

```bash
dig +short api.binaryten.com.br
```

Sem isso o Certbot falha (challenge HTTP nao alcanga a VPS).

---

## Passo 2 — Criar o vhost no Nginx

1. Adicionar o dominio ao `.env` da VPS (`/opt/vps-infra/.env`):

```env
API_DOMAIN=api.binaryten.com.br
```

2. Passar a variavel para o container nginx no `docker-compose.yml`, service `nginx`:

```yaml
    environment:
      S3_DOMAIN: ${S3_DOMAIN}
      CONSOLE_DOMAIN: ${CONSOLE_DOMAIN}
      API_DOMAIN: ${API_DOMAIN}
```

3. Criar o template `nginx/templates/api.conf.template`:

```
server {
    listen 80;
    server_name ${API_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name ${API_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${API_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${API_DOMAIN}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;

    client_max_body_size 10m;

    location / {
        # Nome do container/servico dentro da network
        proxy_pass http://minha-api:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

4. Reconectar o Nginx a rede do compose do app (obrigatorio para resolver o nome do container). Se a API roda em outro compose, defina uma network externa em ambos.

No `docker-compose.yml` da VPS, service `nginx`:

```yaml
    networks:
      - internal
      - edge
      - apps        # <-- adicionar
```

E ao final:

```yaml
networks:
  internal:
    name: vps-infra-internal
  edge:
    name: vps-infra-edge
  apps:
    name: vps-apps
    external: true
```

No compose da API, criar a mesma network e colocar o service nela:

```yaml
networks:
  default:
    name: vps-apps
```

5. Buildar/recriar o nginx para ele processar o novo template (envsubst roda no startpoint da imagem nginx):

```bash
cd /opt/vps-infra
docker compose up -d --build nginx
```

---

## Passo 3 — Emitir o certificado

Os scripts aceitam qualquer dominio como argumento (sem argumento, usam `S3_DOMAIN` e `CONSOLE_DOMAIN`).

```bash
cd /opt/vps-infra

# Dummy cert (permite nginx subir com o 443 do novo dominio)
bash certbot/scripts/create-dummy-certs.sh api.binaryten.com.br

# Recriar nginx processando o novo template
docker compose up -d nginx

# Emitir certificado Let's Encrypt
bash certbot/scripts/init-cert.sh api.binaryten.com.br

# Recarregar nginx (substitui o dummy pelo real)
docker compose exec nginx nginx -s reload
```

---

## Passo 4 — Validar

```bash
curl -I https://api.binaryten.com.br
```

Esperado: resposta da sua aplicacao (200, 307, etc.), **sem** erro de TLS.

Renovacao fica automatica: o cron do `renew.sh` (secao 7.1 do setup-guide) renova **todos** os certificados em `/etc/letsencrypt`, incluindo o novo.

---

## Checklist para cada servico novo

- [ ] Registro `A` no DNS (aguardar propagacao)
- [ ] `*_DOMAIN` no `.env` da VPS
- [ ] Variavel exposta no `environment:` do service `nginx` (compose)
- [ ] Template `nginx/templates/<servico>.conf.template` criado
- [ ] `proxy_pass` aponta para o container (rede `vps-apps`)
- [ ] `docker compose up -d --build nginx`
- [ ] `create-dummy-certs.sh <dominio>`
- [ ] `init-cert.sh <dominio>`
- [ ] `docker compose exec nginx nginx -s reload`
- [ ] `curl -I https://<dominio>`

---

## Proximos servicos

Repetir os 4 passos acima. Nao e necessario mexer em nada do MinIO, do Certbot container, nem do cron de renovacao.

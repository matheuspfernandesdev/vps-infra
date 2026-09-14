# Guia Completo de Setup — VPS Infra (MinIO + Nginx + CertBot)

Este guia cobre a configuracao completa de uma instancia MinIO compartilhada na VPS, exposta publicamente via Nginx com TLS Let's Encrypt.

**Dominio:** `binaryten.com.br`
**Endpoint S3:** `s3.binaryten.com.br`
**Console:** `minio-console.binaryten.com.br`

Siga as secoes **na ordem**. Nao pule a criacao dos certificados dummy (secao 4.5) — sem eles o Nginx nao sobe.

---

## Sumario

1. [Pre-requisitos](#1-pre-requisitos)
2. [Preparacao da VPS](#2-preparacao-da-vps)
3. [Configurar DNS na Hostinger](#3-configurar-dns-na-hostinger)
4. [Deploy da Infraestrutura](#4-deploy-da-infraestrutura)
5. [Configurar Buckets e Access Keys](#5-configurar-buckets-e-access-keys)
6. [Integrar com o Odd Oddities](#6-integrar-com-o-odd-oddities)
7. [Manutencao](#7-manutencao)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Pre-requisitos

| Item | Detalhe |
|---|---|
| VPS | Ubuntu 22.04 LTS ou 24.04 LTS, IP publico |
| Docker | Versao 24+ (pode ja estar instalado) |
| Docker Compose | Plugin v2 (`docker compose`) |
| Dominio | `binaryten.com.br` na Hostinger |
| Portas | 22 (SSH), 80 (HTTP), 443 (HTTPS) |
| Destino na VPS | `/opt/vps-infra` |

Anote o **IP publico da VPS** antes de comecar.

---

## 2. Preparacao da VPS

### 2.1 — Acessar via SSH

```bash
ssh root@<IP_DA_VPS>
```

Se Docker ja estiver instalado e voce ja usa um usuario com sudo, pule para a secao 3.

### 2.2 — Criar usuario nao-root (se ainda nao existir)

```bash
adduser deploy
usermod -aG sudo deploy
```

Configurar chave SSH para o usuario:

```bash
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

Testar em **outro terminal** (nao feche a sessao root ainda):

```bash
ssh deploy@<IP_DA_VPS>
```

A partir daqui, use o usuario `deploy`.

### 2.3 — Configurar firewall UFW

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Resultado esperado:

```
Status: active

To                         Action  From
--                         ------  ----
OpenSSH                    ALLOW   Anywhere
80/tcp                     ALLOW   Anywhere
443/tcp                    ALLOW   Anywhere
```

### 2.4 — Instalar Docker (pular se ja estiver instalado)

```bash
docker --version
docker compose version
```

Se os dois comandos funcionarem, pule para 2.5.

Caso contrario:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Verificar:

```bash
docker --version
docker compose version
```

### 2.5 — Adicionar usuario ao grupo docker

```bash
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

---

## 3. Configurar DNS na Hostinger

> Passo a passo da interface: [hostinger-dns.md](./hostinger-dns.md)

Crie **dois** registros `A` (o campo Nome e so o subdominio, nao o FQDN):

| Tipo | Nome | Aponta para | TTL |
|---|---|---|---|
| `A` | `s3` | IP da VPS | `300` |
| `A` | `minio-console` | IP da VPS | `300` |

**Nao crie registro AAAA (IPv6)** a menos que a VPS tenha IPv6. Let's Encrypt tenta IPv6 primeiro e a emissao do certificado falha.

Aguarde a propagacao e confirme **na sua maquina local**:

```bash
dig +short s3.binaryten.com.br
dig +short minio-console.binaryten.com.br
```

Os dois devem retornar o IP da VPS. So avance quando isso estiver correto.

---

## 4. Deploy da Infraestrutura

### 4.1 — Colocar o repositorio na VPS

Na VPS:

```bash
sudo mkdir -p /opt/vps-infra
sudo chown deploy:deploy /opt/vps-infra
```

Na **sua maquina local** (PowerShell), a partir da pasta `vps-infra`:

```powershell
scp -r * deploy@<IP_DA_VPS>:/opt/vps-infra/
```

Ou, se o repo ja estiver no Git:

```bash
cd /opt/vps-infra
git clone <REPO_URL> .
```

### 4.2 — Corrigir quebra de linha dos scripts (obrigatorio se copiou do Windows)

```bash
cd /opt/vps-infra
sed -i 's/\r$//' certbot/scripts/*.sh minio/*.sh
chmod +x certbot/scripts/*.sh minio/init-buckets.sh
```

### 4.3 — Configurar o `.env`

```bash
cd /opt/vps-infra
cp .env.example .env
nano .env
```

Preencha:

```env
S3_DOMAIN=s3.binaryten.com.br
CONSOLE_DOMAIN=minio-console.binaryten.com.br
EMAIL=seu-email@binaryten.com.br

MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=<cole-aqui-a-senha>
```

Gerar a senha root do MinIO:

```bash
openssl rand -base64 32
```

Regras: `MINIO_ROOT_USER` minimo 3 caracteres; `MINIO_ROOT_PASSWORD` minimo 8 (use 32+). Guarde no password manager.

### 4.4 — Gerar basic auth do Console

```bash
cd /opt/vps-infra
cp security/.htpasswd.example security/.htpasswd
openssl passwd -apr1
```

Digite a senha duas vezes. O comando imprime um hash (`$apr1$...`).

```bash
nano security/.htpasswd
```

Deixe **uma unica linha**, sem comentarios:

```
admin:$apr1$xxxxxxxx$yyyyyyyyyyyyyyyyyyyyy
```

Essa senha e a **primeira** barreira do Console (Nginx). Depois ainda entra com o usuario root do MinIO.

### 4.5 — Criar certificados dummy (obrigatorio)

O Nginx recusa subir o bloco 443 se os arquivos de certificado nao existirem. Os dummy resolvem o ovo-e-galinha; o Certbot troca por certificados reais na 4.7.

```bash
cd /opt/vps-infra
bash certbot/scripts/create-dummy-certs.sh
```

Saida esperada: `Dummy certificate created for s3.binaryten.com.br` e o mesmo para o console.

### 4.6 — Subir MinIO e Nginx

```bash
cd /opt/vps-infra
docker compose up -d minio nginx
docker compose ps
```

Esperado: `vps-minio` **healthy**, `vps-nginx` **Up**.

Se o Nginx cair:

```bash
docker compose logs nginx
```

Causa mais comum: dummy certs nao criados ou `.htpasswd` ausente.

### 4.7 — Emitir certificados Let's Encrypt

DNS ja deve estar apontando para esta VPS (secao 3). Porta 80 precisa estar acessivel da internet.

```bash
cd /opt/vps-infra
bash certbot/scripts/init-cert.sh
```

O script emite **dois** certificados separados (um por dominio), porque o Nginx procura:

- `/etc/letsencrypt/live/s3.binaryten.com.br/`
- `/etc/letsencrypt/live/minio-console.binaryten.com.br/`

### 4.8 — Recarregar Nginx

```bash
docker compose exec nginx nginx -s reload
```

### 4.9 — Validar

```bash
curl -I https://s3.binaryten.com.br/minio/health/live
# HTTP/2 200

curl -I https://minio-console.binaryten.com.br
# HTTP/2 401  (basic auth do Nginx)

curl -I -u admin:SENHA_DO_HTPASSWD https://minio-console.binaryten.com.br
# HTTP/2 200 ou 302
```

No navegador: `https://minio-console.binaryten.com.br` → basic auth Nginx → tela de login MinIO (root user / root password do `.env`).

---

## 5. Configurar Buckets e Access Keys

### 5.1 — Criar buckets e policies

MinIO **nao** esta publicado na internet. As portas 9000/9001 existem so em `127.0.0.1`. O script usa a rede Docker interna.

```bash
cd /opt/vps-infra
bash minio/init-buckets.sh
```

Cria:

| Bucket | Policy IAM |
|---|---|
| `odd-oddities-dev` | `odd-oddities-dev` |
| `odd-oddities-prod` | `odd-oddities-prod` |

A cota de 20 GB do Odd Oddities e aplicada **pelo worker** (BR-009), nao pelo MinIO.

### 5.2 — Criar Access Keys no Console

1. Abra `https://minio-console.binaryten.com.br`
2. Basic auth do Nginx, depois login root do MinIO
3. Menu **Access Keys** → **Create access key**
4. Crie **duas** chaves:

| Uso | Policy |
|---|---|
| Odd Oddities dev | `odd-oddities-dev` |
| Odd Oddities prod | `odd-oddities-prod` |

5. Copie Access Key e Secret Key na hora (o secret nao aparece de novo)

Se a UI nao deixar anexar a policy na criacao, crie a chave e depois edite para restringir ao bucket. Sem policy, a chave herda permissao de root — nao use isso nos projetos.

### 5.3 — Conferir buckets

```bash
docker run --rm --network vps-infra-internal --entrypoint /bin/sh minio/mc:latest -c \
  "mc alias set local http://minio:9000 'MINIO_ROOT_USER' 'MINIO_ROOT_PASSWORD' && mc ls local"
```

Substitua usuario e senha pelos valores do `.env`.

---

## 6. Integrar com o Odd Oddities

O `docker-compose.yml` do Odd Oddities ja aponta para o MinIO compartilhado. So preencha o `.env` do projeto.

### Dev

```env
MINIO_ACCESS_KEY=<access-key-dev>
MINIO_SECRET_KEY=<secret-key-dev>
MINIO_BUCKET_NAME=odd-oddities-dev
STORAGE_DOMAIN=s3.binaryten.com.br
```

### Prod

```env
MINIO_ACCESS_KEY=<access-key-prod>
MINIO_SECRET_KEY=<secret-key-prod>
MINIO_BUCKET_NAME=odd-oddities-prod
STORAGE_DOMAIN=s3.binaryten.com.br
```

O worker usa:

- `Endpoint=https://s3.binaryten.com.br` — upload/list
- `PublicEndpoint=https://s3.binaryten.com.br` — URL pre-assinada (Meta)

Os servicos `minio`, `nginx` e `certbot` **nao** devem existir no compose do Odd Oddities.

---

## 7. Manutencao

### 7.1 — Renovacao do certificado

O Certbot nao fica rodando. Um cron emite a renovacao e recarrega o Nginx:

```bash
crontab -e
```

```cron
0 3 * * * cd /opt/vps-infra && /opt/vps-infra/certbot/scripts/renew.sh >> /var/log/vps-infra-renew.log 2>&1
```

Let's Encrypt renova quando falta menos de 30 dias. O `nginx -s reload` e obrigatorio — sem ele o processo continua com o certificado antigo em memoria.

### 7.2 — Logs

```bash
cd /opt/vps-infra
docker compose logs -f minio
docker compose logs -f nginx
```

### 7.3 — Saude

```bash
docker compose ps
docker compose exec nginx nginx -t
curl -I https://s3.binaryten.com.br/minio/health/live
```

### 7.4 — Backup

```bash
mkdir -p /opt/vps-infra/backup

docker run --rm -v vps-infra-minio-data:/data -v /opt/vps-infra/backup:/backup alpine \
  tar czf /backup/minio-$(date +%Y%m%d).tar.gz -C /data .

docker run --rm -v vps-infra-certbot-conf:/data -v /opt/vps-infra/backup:/backup alpine \
  tar czf /backup/certbot-$(date +%Y%m%d).tar.gz -C /data .
```

### 7.5 — Atualizar imagens

```bash
cd /opt/vps-infra
docker compose pull minio
docker compose up -d minio
docker compose build nginx
docker compose up -d nginx
```

---

## 8. Troubleshooting

| Sintoma | Causa | Solucao |
|---|---|---|
| Nginx reinicia em loop, log `cannot load certificate` | Dummy certs nao criados | Rodar `bash certbot/scripts/create-dummy-certs.sh` e `docker compose up -d nginx` |
| `S3_DOMAIN is required` nos scripts | `.env` nao existe ou nao foi preenchido | `cp .env.example .env` e editar |
| `$'\r': command not found` | Scripts com CRLF do Windows | `sed -i 's/\r$//' certbot/scripts/*.sh minio/*.sh` |
| Certbot: connection refused / timeout | DNS errado, firewall ou Nginx fora | `dig +short s3.binaryten.com.br`; `sudo ufw status`; `docker compose ps` |
| Certbot: unauthorized / 404 no challenge | Volume ACME ou server_name | Conferir `S3_DOMAIN` no `.env` e `docker compose logs nginx` |
| Certificado do console nao existe | Um unico cert SAN nos dois dominios | Este repo emite **dois** certs. Use `init-cert.sh` atual |
| 502 Bad Gateway | MinIO nao healthy | `docker compose logs minio` |
| `mc` em `localhost:9000` falha de fora da VPS | Porta 9000 so escuta em 127.0.0.1 | Use o script `init-buckets.sh` ou `127.0.0.1` via SSH |
| 401 no Console | `.htpasswd` errado | Regenerar hash e recarregar Nginx |
| Upload S3 falha com redirect | Cliente usando `http://` | Endpoint do worker deve ser `https://s3.binaryten.com.br` |
| Let's Encrypt falha com IPv6 | Registro AAAA sem IPv6 na VPS | Remover AAAA na Hostinger |
| `error mounting .htpasswd` | Arquivo nao criado | `cp security/.htpasswd.example security/.htpasswd` e editar |
| Worker na VPS nao alcança `s3.binaryten.com.br` | Hairpin NAT | No compose do app: `extra_hosts: ["s3.binaryten.com.br:host-gateway"]` |
| `Conflict: container name vps-certbot` | Container de um `run` anterior | `docker rm -f vps-certbot` e repetir o script |

---

## Referencias

- [Adicionar um novo servico (API/MVC) com HTTPS](./add-new-service.md)
- [Configuracao DNS na Hostinger](./hostinger-dns.md)
- [Gerenciamento de Buckets](./bucket-management.md)

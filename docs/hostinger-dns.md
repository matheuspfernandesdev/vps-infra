# Configuracao DNS na Hostinger

Passo a passo para apontar `s3.binaryten.com.br` e `minio-console.binaryten.com.br` para a VPS.

---

## Pre-requisitos

- Conta Hostinger com o dominio `binaryten.com.br`
- IP publico da VPS anotado

---

## Passo 1 — Abrir a zona DNS

1. Acesse [hpanel.hostinger.com](https://hpanel.hostinger.com) e faca login
2. Menu **Dominios**
3. Clique em `binaryten.com.br`
4. **DNS / Nameservers** (ou **Zona DNS** / **DNS Zone Editor**)

Os nomes dos menus mudam um pouco entre versoes do hPanel. O objetivo e a lista de registros DNS do dominio.

---

## Passo 2 — Registro A do endpoint S3

| Campo | Valor |
|---|---|
| Tipo | `A` |
| Nome / Host | `s3` |
| Aponta para / Valor | IP da VPS |
| TTL | `300` |

O Nome e **somente** `s3`. Nao use `s3.binaryten.com.br` nesse campo — a Hostinger concatena o dominio sozinha.

Salve o registro.

---

## Passo 3 — Registro A do Console

| Campo | Valor |
|---|---|
| Tipo | `A` |
| Nome / Host | `minio-console` |
| Aponta para / Valor | IP da VPS |
| TTL | `300` |

Salve o registro.

---

## Passo 4 — Nao criar AAAA (IPv6)

Se existir registro `AAAA` para `s3` ou `minio-console` e a VPS **nao** tiver IPv6, apague o AAAA.

Let's Encrypt tenta IPv6 primeiro. Sem escuta IPv6 na VPS, a emissao do certificado falha com timeout.

---

## Passo 5 — Verificar propagacao

Na sua maquina local:

```bash
dig +short s3.binaryten.com.br
dig +short minio-console.binaryten.com.br
```

No Windows (PowerShell):

```powershell
nslookup s3.binaryten.com.br
nslookup minio-console.binaryten.com.br
```

Os dois devem retornar o IP da VPS.

Se estiver vazio ou com IP antigo:

- Confirme que o registro foi salvo
- Aguarde o TTL (300 segundos) e o cache do ISP
- Confira em [dnschecker.org](https://dnschecker.org)

So rode o Certbot **depois** dessa verificacao.

---

## Passo 6 — Teste HTTP (depois do Nginx no ar)

```bash
curl -I http://s3.binaryten.com.br
```

Esperado: `301` para HTTPS, ou `200` no path `/.well-known/acme-challenge/` durante a emissao.

HTTPS so funciona depois do Let's Encrypt ([setup-guide.md](./setup-guide.md) secao 4.7).

---

## Troubleshooting

| Problema | Causa | Solucao |
|---|---|---|
| `dig` retorna IP errado | Registro duplicado ou TTL antigo | Apague duplicatas; aguarde TTL |
| `dig` vazio | Registro nao salvo ou Nome com FQDN | Nome deve ser `s3`, nao `s3.binaryten.com.br` |
| Certbot timeout IPv6 | AAAA sem IPv6 na VPS | Remover AAAA |
| `curl` connection refused | Firewall | `sudo ufw status` — 80 e 443 ALLOW |
| `curl` timeout | Porta fechada no provedor da VPS | Liberar 80/443 no painel da VPS (alem do UFW) |

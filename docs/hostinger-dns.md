# Configuracao DNS na Hostinger

Passo a passo para apontar `s3.binaryten.com.br` e `minio-console.binaryten.com.br` para a VPS.

---

## Pre-requisitos

- Conta Hostinger com o dominio `binaryten.com.br`
- IP publico da VPS anotado

---

## Passo 0 — Confirmar quem REALMENTE serve a zona DNS

**Antes de criar qualquer registro.** O editor da Hostinger so funciona se os nameservers do dominio apontarem para a Hostinger. Se apontam para outro provedor, o editor fica "inativo" e tudo que voce criar la e ignorado — o dominio pode estar na Hostinger so como **registradora** (quem cobra a renovacao), enquanto a **zona DNS** vive em outro lugar.

A cadeia tem tres elos:

```
1. Registro (Registro.br)          → prova de posse do dominio
2. Nameservers (delegacao)         → a quem o mundo inteiro faz as perguntas
3. Zona DNS (no provedor dos NS)   → onde os registros (A, CNAME, CAA...) moram
```

`Registrar` nao e `servidor DNS`. Ao conectar um dominio num projeto Vercel, o assistente oferece trocar os nameservers para `ns1/ns2.vercel-dns.com` — se isso foi aceito, a **Vercel passou a ser a dona da zona**, e a Hostinger virou so o lugar onde se troca o telefone sem fio.

Descobrir onde esta a zona (maquina local):

```powershell
Resolve-DnsName binaryten.com.br -Type NS
```

| Nameservers retornados | Os registros A vao ser criados em |
|---|---|
| `ns1/ns2.hostinger.com` | Hostinger (Passo 1 abaixo) |
| `ns1/ns2.vercel-dns.com` | **Vercel** (caso atual de `binaryten.com.br` — ver abaixo) |
| `ns1/ns2.cloudflare.com` | Cloudflare DNS |

### Caso atual: zona servida pela Vercel

1. Abrir `vercel.com/dashboard` → **Domains** → `binaryten.com.br` → rolar ate **DNS Records**
2. No formulario (Name/Type/Value/TTL), criar os dois registros `A` dos Passos 2 e 3 abaixo
3. **Cuidado com o Value pre-preenchido** (`76.76.21.21` — edge da Vercel). Trocar sempre pelo IP da VPS
4. TTL: a Vercel aceita `60` (minimo dela) — propaga mais rapido que os 300 sugeridos

A zona da Vercel tem um registro `ALIAS *` (wildcard) criado automaticamente — por isso qualquer subdominio aleatorio resolve para a edge deles. Registro **exato** (o `A` de `s3`) tem precedencia sobre wildcard, entao criar os dois registros nao afeta o site existente.

### CAA — o registro que pode travar o Let's Encrypt

Registros `CAA` dizem **quais autoridades certificadoras podem emitir certificado** para o dominio. Se a Let's Encrypt nao estiver listada, o Certbot falha na secao 4.7 mesmo com portas, DNS e Nginx perfeitos (erro do tipo `CAA check failed` / `not permitted`).

A Vercel cria CAA propria (`0 issue "pki.goog"`) para o certificado dela. Multiplos registros CAA no mesmo nome **se somam**: se ao menos um autorizar, pode emitir.

Consultar (PowerShell 5.1 nao tem tipo CAA — usar DNS-over-HTTPS):

```powershell
(Invoke-RestMethod "https://dns.google/resolve?name=binaryten.com.br&type=CAA").Answer
```

Para `binaryten.com.br` a zona ja responde:

```
0 issue "pki.goog"
0 issue "letsencrypt.org"    ← emissao Let's Encrypt autorizada
0 issue "sectigo.com"
```

Os subdominios `s3` e `minio-console` herdam o CAA do apex (nenhum CAA proprio), entao **nenhuma acao extra** e necessaria. Se algum dia aparecer erro de CAA no Certbot, criar um registro `CAA` para `s3` com value `0 issue "letsencrypt.org"` — CAA exato no nome sobrepoe a heranca do pai.

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

#### Entendendo de onde veio a resposta

`nslookup` pode mostrar `Nao e resposta autoritativa` (`Non-authoritative answer` em ingles) com `Address: fe80::1` — isso significa que a resposta veio do **cache local** (roteador/ISP), nao do nameservers autoritativo do dominio. E util para ver a sua maquina ja enxerga o novo IP, mas nao prova que o mundo inteiro ve.

Para perguntar **a autoridade em si** (ignora caches no meio):

```powershell
# troque o -Server conforme quem serve a zona (Passo 0)
Resolve-DnsName s3.binaryten.com.br -Server ns1.vercel-dns.com
Resolve-DnsName minio-console.binaryten.com.br -Server ns1.vercel-dns.com
```

Para perguntar a um **resolvedor publico independente** (o que o resto do mundo ve) e confirmar de que **nao ha IPv6**, via DNS-over-HTTPS:

```powershell
# esperado: data = IP da VPS
(Invoke-RestMethod "https://dns.google/resolve?name=s3.binaryten.com.br&type=A").Answer

# esperado: VAZIO — sem AAAA, o Let's Encrypt nao tenta IPv6 e a emissao nao falha
(Invoke-RestMethod "https://dns.google/resolve?name=s3.binaryten.com.br&type=AAAA").Answer
```

`Answer` vazio com `Status = 0` e o caso `NOERROR/NODATA`: o nome existe, mas nao ha registro daquele tipo — exatamente o desejado para o AAAA.

O DoH (HTTPS para `dns.google` ou `cloudflare-dns.com/dns-query`) e tambem a saida para limitacao de ferramenta: PowerShell 5.1 nao reconhece o tipo `CAA` no `Resolve-DnsName` e o `nslookup` responde `unknown query type: CAA` — via DoH qualquer tipo funciona.

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
| Registro criado na Hostinger mas `dig` nao mostra | Nameservers apontam para outro provedor (zona nao e da Hostinger) | Passo 0: criar o registro onde os NS servem a zona |
| Certbot: `CAA check failed` / `not permitted` | Registro CAA nao autoriza a Let's Encrypt | Consultar CAA via DoH (Passo 0) e criar `CAA` no subdominio com `0 issue "letsencrypt.org"` |
| Subdominio "aleatorio" resolve para Vercel/CDN | Registro wildcard (`*`) na zona | Normal; registro `A` exato tem precedencia — nao e preciso apagar o wildcard |
| `dig` retorna IP errado | Registro duplicado ou TTL antigo | Apague duplicatas; aguarde TTL |
| `dig` vazio | Registro nao salvo ou Nome com FQDN | Nome deve ser `s3`, nao `s3.binaryten.com.br` |
| Certbot timeout IPv6 | AAAA sem IPv6 na VPS | Remover AAAA |
| `curl` connection refused | Firewall | `sudo ufw status` — 80 e 443 ALLOW |
| `curl` timeout | Porta fechada no provedor da VPS | Liberar 80/443 no painel da VPS (alem do UFW) |

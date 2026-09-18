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

#### Preciso criar o usuario mesmo se ja tenho servicos publicados?

Sim. Criar um usuario e uma acao **aditiva**: nao toca em containers, servicos ou arquivos que ja rodam. O ganho e o **principio do minimo privilegio** — voce para de operar como root, entao um `rm -rf` errado ou um container root comprometido custa menos. Alem disso o resto do guia depende do `deploy` (4.1 faz `chown deploy:deploy /opt/vps-infra` e o `scp` vai para `deploy@IP`).

Antes de criar, inventarie o que ja existe na VPS (todos os comandos sao somente leitura):

```bash
id deploy                          # usuario ja existe?
ss -tlnp | grep -E ':(80|443)\s'   # quem ocupa 80/443 hoje?
docker ps -a                       # containers, inclusive parados
```

O que procurar:

| Cheque | Porque importa para este guia |
|---|---|
| Alguem escutando em 80/443 | Se houver, o `docker compose up` da 4.6 falha com `address already in use` |
| Portas publicadas por containers existentes | Conflito direto com as portas do host |
| Nome de container/rede iniciando com `vps-` | `container_name` duplicado faz o compose recusar subir |
| `restart: always`/`unless-stopped` | O servico volta sozinho apos reboot — precisa conviver, nao so parar uma vez |

#### A senha pedida pelo adduser

O `adduser deploy` pede uma senha. Ela **nao** e usada para logar via SSH (a chave cuida disso). Ela e a senha do **`sudo`**: quem autoriza o `deploy` a fazer operacoes de root, pedida em todo `sudo` futuro. Gere uma forte e guarde no password manager:

```bash
openssl rand -base64 18
```

Os campos de geoinformacao (nome, telefone...) que vao em seguida sao todos opcionais — `Enter` em cada um e confirme com `Y`.

#### O warning da primeira conexao SSH

Ao rodar `ssh deploy@<IP_DA_VPS>` pela primeira vez, aparece:

```
The authenticity of host ... can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Nao e um erro.** E a protecao contra man-in-the-middle: o cliente SSH ainda nao viu a host key daquele endereco e pede para confirmar a impressao digital. Digitar `yes` grava a chave em `~/.ssh/known_hosts` do usuario que esta conectando, e nunca mais pergunta.

Para conferir que o hash apresentado bate com a chave real do servidor:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Depois do `yes`, o banner `Welcome to Ubuntu` confirma que a **autenticacao por chave funcionou** — esse e o ponto critico do teste, e por isso ele roda em outro terminal sem fechar a sessao root.

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
OpenSSH (v6)               ALLOW   Anywhere (v6)
80/tcp (v6)                ALLOW   Anywhere (v6)
443/tcp (v6)               ALLOW   Anywhere (v6)
```

As linhas `(v6)` sao normais: o UFW aplica as mesmas regras ao IPv6. O que importa para o Let's Encrypt e **nao** criar registro AAAA no DNS (secao 3) — isso e outra camada, nao o firewall.

#### Por que apenas 22, 80 e 443?

**UFW (Uncomplicated Firewall)** e o firewall padrao do Ubuntu, um front-end amigavel do `iptables`/`nftables` do kernel. Sem ele, toda porta que um servico escutar fica exposta para o mundo inteiro. Com ele ativo, so passam as portas liberadas explicitamente.

| Porta | Por que fica aberta |
|---|---|
| 22 (OpenSSH) | Gerencia via SSH. Liberada **antes** do `ufw enable`, senao voce se tranca fora da VPS |
| 80/tcp | Desafio HTTP-01 do Let's Encrypt (secao 4.7) e redirect para HTTPS |
| 443/tcp | Todo o trafego real (S3 e Console) passa pelo Nginx com TLS |

As portas do MinIO (9000/9001) **nao** sao liberadas porque escutam apenas em `127.0.0.1` e na rede Docker interna (secao 5.1). O mundo externo so ve o 443. Como o Nginx roteia por dominio, voce pode hospedar N servicos atras das mesmas duas portas.

O perigo de deixar uma porta exposta "mesmo sem usar":

- **Bots varrem a internet inteira 24/7.** Qualquer servico que vazar para `0.0.0.0` (Redis, API do Docker, MinIO em 9000/9001) e encontrado em horas — sem nem passar pelo basic auth do Nginx.
- **Docker fura o UFW.** O Docker escreve regras direto no iptables (ver abaixo), entao uma porta publicada por container fica aberta mesmo com o firewall ativo. Por isso o guia binda o MinIO em `127.0.0.1` em vez de confiar no firewall.
- "Nao estou usando" vale ate o primeiro `docker run -p` distrado ou uma atualizacao que muda o bind.
- Firewall negando em silencio nao gera ruido; um servico exposto sendo explorado voce so descobre depois.

#### iptables — onde o firewall realmente acontece

O **iptables** e o mecanismo de baixo nivel do kernel Linux: a tabela de regras onde o filtro de pacotes de fato roda (aceitar, descartar, redirecionar por porta/IP/protocolo). O UFW e so uma interface humana que escreve regras la. Em Ubuntu 22.04+ o comando `iptables` ja e um wrapper do **nftables** (sucessor moderno), mas o conceito e o mesmo.

```
UFW (interface simples, humana)
   ↓ escreve regras em
iptables / nftables (backend do kernel)
   ↓ que o Docker tambem manipula
diretamente (por isso ele "fura" o UFW)
```

Voce raramente vai editar iptables manualmente neste projeto — basta saber que ele existe para entender por que o UFW sozinho nao segura porta publicada por container.

#### O caminho de uma requisicao ate o MinIO

Cada camada decide em um nivel diferente do trafego de rede:

```
Internet
   │  pacote: IP da VPS :443
   ▼
1. iptables (filter)          ← UFW escreve aqui
   "443 esta liberado? sim → deixa passar; 9000? nao → descarta"
   Decide POR PORTA/IP (camada 4), nao olha conteudo
   │
   ▼
2. iptables (NAT/DNAT)        ← Docker escreve aqui
   host:443 → container nginx:443
   (o mapeamento do `ports:` do compose)
   │
   ▼
3. Nginx (reverse proxy, camada 7)
    termina TLS (cert Let's Encrypt) e le o HOST:
    s3.binaryten.com.br        → proxy_pass http://minio:9000
    minio-console.binaryten... → proxy_pass http://minio:9001
    Decide POR DOMINIO/PATH — coisa que o UFW nao consegue fazer
   │
   ▼
4. Rede Docker interna (vps-infra-internal)
   minio:9000/9001 so existem aqui — nunca alcancaveis de fora
```

Resumo: **UFW e o porteiro que decide o que pode entrar; o NAT do Docker e a passagem host→container; o Nginx e o recepcionista que encaminha para a sala certa pelo nome no cracha (dominio)**. Uma requisicao nunca chega direto na aplicacao — entra por 80/443 e e roteada por nome, nunca por porta.

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

#### Por que `newgrp` e necessario?

A filiacao a grupos e resolvida **no momento do login** e fica gravada no token da sessao. O `usermod` edita o `/etc/group` na hora, mas a sessao atual continua com o token antigo — sem o grupo `docker`. O `newgrp docker` abre um shell novo com o grupo ja aplicado, entao o `docker run` funciona sem sair e voltar. Alternativa equivalente: fechar o SSH e logar de novo.

Se pular o `newgrp`, o erro e:

```
permission denied while trying to connect to the Docker daemon socket
```

#### O grupo docker e um root equivalente (atencao de seguranca)

O daemon Docker roda como root. Dar acesso ao socket (`/var/run/docker.sock`) para um usuario sem sudo significa que ele pode:

- Criar um container montando o filesystem inteiro do host: `docker run -v /:/host busybox sh -c "echo ... >> /host/etc/shadow"` — escrita como root na hospedeira
- Rodar containers `--privileged` e escapar para o host

Ou seja: **quem esta no grupo `docker` e de fato um admin da maquina**, com o `usermod` do exemplo como unica diferenca de burocracia. Adicione ao grupo apenas usuarios nos quais voce confiaria um shell root.

#### O que cada comando valida

| Comando | O que comprova |
|---|---|
| `usermod -aG docker $USER` | Persiste a filiacao no `/etc/group` (o `-a` e crucial: sem ele, `-G` **substitui** todos os outros grupos do usuario, inclusive `sudo`) |
| `newgrp docker` | Aplica o grupo na sessao atual |
| `docker run hello-world` | Ponteira final: `deploy` fala com o daemon sem `sudo`, e o daemon consegue baixar imagem e criar container |

Bonus: como o daemon e compartilhado na maquina, o `deploy` tambem consegue gerenciar containers criados pelo root (ex.: parar/reiniciar workers de outros projetos). O dono dos arquivos na imagem/volume nao muda — o controle vem do socket.

---

## 3. Configurar DNS na Hostinger

> Passo a passo da interface: [hostinger-dns.md](./hostinger-dns.md)

> **Antes:** confirme ONDE a zona DNS vive. A Hostinger pode ser so a registradora — se os nameservers do dominio apontam para outro provedor (ex.: `ns1/ns2.vercel-dns.com`), os registros devem ser criados **la**, e o editor da Hostinger fica inerte. Checar: `Resolve-DnsName binaryten.com.br -Type NS`. Detalhes e o caso Vercel (incluindo checagem de CAA para o Let's Encrypt) no Passo 0 de [hostinger-dns.md](./hostinger-dns.md).

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

**Preparo (uma vez, como `deploy`):**

```bash
sudo mkdir -p /opt/vps-infra
sudo chown deploy:deploy /opt/vps-infra
```

#### Opcao A (recomendada): git clone via Deploy Key SSH

O repo `matheuspfernandesdev/vps-infra` e **privado**, e o git nao envia mais credenciais por senha. Tentar clonar via HTTPS com a senha da conta falha com:

```
remote: Invalid username or token. Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/.../'
```

As duas saidas para repo privado: HTTPS + **token** (PAT) ou SSH + **deploy key**. A deploy key e melhor:

| | HTTPS + PAT | SSH deploy key |
|---|---|---|
| Escopo | Credencial da **conta** (escopo amplo) | Um **unico repo** |
| Acesso | Pode escrever se o escopo deixar | **Somente leitura** (sem "Allow write access") |
| Se a VPS for comprometida | Token exige rotacao imediata | Nada pode ser alterado no repo pela chave |
| Validade | PAT expira (configuravel) | Sem validade |

O "leia e use o scp" tambem resolve, mas o repo da VPS fica desvinculado do git: atualizar passa a ser repetir o scp.

> **NUNCA** clone com o token na URL (`https://TOKEN@github.com/...`): ele fica gravado em texto puro no `.git/config` e no historico de shell.

**A1 — Gerar o par de chaves na VPS (como `deploy`):**

```bash
ssh-keygen -t ed25519 -C "vps-infra-deploy" -f ~/.ssh/id_ed25519_github -N ""
cat ~/.ssh/id_ed25519_github.pub
```

Copie a linha impressa (comeca com `ssh-ed25519 ...`) — essa e a **publica**, e a unica que sai da maquina. O `-N ""` (sem passphrase) e aceitavel aqui: a chave so le codigo ja publicavel no repo e nao da acesso a nada sensivel da VPS. A privada (`id_ed25519_github`, sem `.pub`) nunca deve ser copiada para outro lugar.

Anatomia do arquivo `.pub` (uma linha, tres campos separados por espaco):

```
ssh-ed25519 AAAAC3NzaC1...C1lEMT5AAAAI... vps-infra-deploy
└────┬─────┘ └─────────────────────────┘ └──────┬───────┘
 algoritmo       chave publica (base64)      comentario (-C)
```

Cole a **linha inteira** no GitHub. Colar so o blob do meio ate funciona, mas o formato esperado e a linha completa; o comentario e apenas rotulo humano para identificar a maquina na listagem de keys.

**A2 — Cadastrar no GitHub:**

Repo → **Settings** → **Deploy keys** → **Add deploy key**

- Title: `vps-deploy` (identifica a maquina)
- Key: cola a publica do A1
- **Deixe "Allow write access" DESMARCADO** — e isso que torna a chave read-only
- Add key

**A3 — Ensinar o SSH a usar essa chave** (o padrao do ssh so considera `~/.ssh/id_ed25519`; como o nome e customizado, aponte explicitamente):

```bash
printf 'Host github.com\n  IdentityFile ~/.ssh/id_ed25519_github\n  IdentitiesOnly yes\n' >> ~/.ssh/config
```

`IdentitiesOnly yes`: tenta **somente** essa chave contra o github.com — evita o erro classico `Permission denied (publickey)` quando o ssh oferece outras chaves primeiro e esgota o limite de tentativas do servidor.

**A4 — Testar a autenticacao:**

```bash
ssh -T git@github.com
```

Esperado: `Hi matheuspfernandesdev/vps-infra! You've successfully authenticated, but GitHub does not provide shell access.`

Com deploy key, o GitHub responde com o **nome do repo**, nao o seu usuario — se aparecer `Hi matheuspfernandesdev!` sem o repo, a chave foi cadastrada no perfil pessoal (Settings → SSH keys) em vez das Deploy keys do repo; mova-a.

**A5 — Clonar:**

```bash
cd /opt/vps-infra
ls -A   # so pode clonar com o diretorio VAZIO (um clone que falhou no meio pode ter deixado lixo)
git clone git@github.com:matheuspfernandesdev/vps-infra.git .
```

O `.` final clona no diretorio atual. Confirme `git status` limpo antes de seguir. Daqui pra frente, atualizar a infra e: `git pull` + secao 7.5.

#### Opcao B (alternativa): scp da maquina local

Sem git na VPS e sem credenciais. Na **sua maquina local** (PowerShell), a partir da pasta `vps-infra`:

```powershell
scp -r * deploy@<IP_DA_VPS>:/opt/vps-infra/
```

Serve para o primeiro deploy, mas nao deixa trilha de versionamento: update = repetir o scp, e voce nao sabe o que esta rodando versus o que esta no git.

Em qualquer opcao: `.env` fica **fora do git** (gitignored) e e criado na VPS no Passo 4.3 — por isso clonar nao expoe segredo nenhum. O arquivo `security/.htpasswd` legado nao e mais usado (Console sem basic auth desde o fix `api/v1/session 401`).

### 4.2 — Ajustar quebra de linha e permissao de execucao (geralmente desnecessario)

```bash
cd /opt/vps-infra
sed -i 's/\r$//' certbot/scripts/*.sh minio/*.sh
chmod +x certbot/scripts/*.sh minio/init-buckets.sh
```

> **Geralmente desnecessario.** O repo ja tem um `.gitattributes` na raiz com `*.sh text eol=lf`, e os scripts estao rastreados como executaveis (modo `100755`). Em uma VPS fresca, apos `git clone`, os arquivos ja chegam em LF e com `+x` preservado — `sed` e `chmod` sao **no-ops**.
>
> Rode os dois comandos **apenas** se algum script quebrar com erro do tipo `$'\r': command not found` (CRLF) ou `Permission denied` (sem `+x`). Sao a rede de seguranca, nao o caminho feliz.

#### Por que esses comandos ja foram obrigatorios (e nao sao mais)

Historico do problema:

- O repo nasceu em um sistema Windows; o git grava CRLF por padrao em `.sh`, e o bit `+x` nao e trackeavel em NTFS
- Quem clonava em Linux via SSH recebia CRLF (script quebrava com `\r`) e sem permissao de execucao
- O 4.2 era o "remendo" obrigatorio antes do 4.6

A correcao definitiva foi feita em dois commits do repo:

1. `.gitattributes` (`*.sh text eol=lf`) — git normaliza `.sh` para LF no checkout e no commit, **sobrescrevendo** o `core.autocrlf` global. O `sed` do 4.2 passa a ser no-op
2. `core.fileMode true` + `git update-index --chmod=+x` — grava o bit `100755` no objeto tree. Em qualquer clone Linux, o `+x` e preservado, e `chmod` deixa de ser necessario

#### Por que recomendo manter o 4.2 como verificacao (nao remover)

- Quem usa `scp` (Opcao B da 4.1) em vez de `git clone` recebe arquivos com bits de permissao do cliente SSH, nao do git — o `chmod +x` ainda e necessario nesse caminho
- Caso alguem tenha `core.autocrlf=true` no `.gitconfig` global, o `.gitattributes` aqui no repo vence para `*.sh`, mas e bom ter o comando na manga se aparecer CRLF em qualquer outro arquivo

#### O efeito colateral que motivou esta secao (historico)

Quando o `chmod +x` era obrigatorio, o git passava a enxergar a working tree como "modificada" apos cada setup (modo mudou de `100644` para `0755` no filesystem, mas o index ainda tinha `100644`). O proximo `git pull` abortava com:

```
error: Your local changes to the following files would be overwritten by merge
Aborting
```

Resolvido agora com o `+x` rastreado no repo. **Se voce esta fazendo o pull que traz este fix e caiu no erro acima, a recuperacao e:** `git checkout -- . && git pull` — depois `ls -l` deve mostrar `-rwxr-xr-x` e `git status` limpo. Se voce vir esse erro no futuro apos o pull, significa que algum script novo chegou sem `+x` no tree — rode o `chmod` e abra uma PR para corrigir no repo tambem (`git update-index --chmod=+x ...` + commit).

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

> **Salvando no nano:** `Ctrl+O` **seguido de `Enter`** (o nano pergunta o nome do arquivo; sem o Enter ele fica travado esperando) grava; `Ctrl+X` sai. No Ubuntu 24.04 o `Ctrl+S` tambem salva direto. `Ctrl+K` corta a linha inteira — util para limpar placeholders sem apagar metade dela por engano.

### 4.4 — Basic auth do Console (removido)

> **Removido.** Versoes anteriores usavam `auth_basic` do Nginx (`security/.htpasswd`) como portaria antes do login do MinIO. O duplo auth quebra o Console: o `fetch` JS em `GET /api/v1/session` nao envia o header Basic, o Nginx responde `401` antes do MinIO e a SPA fica branca apos o login. O Console agora usa **apenas** o auth nativo do MinIO (`MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` da secao 4.3). O arquivo `security/.htpasswd` legado permanece no repo como exemplo mas **nao e montado nem exigido** — `docker compose up` nao falha se ele nao existir. Se quiser reativar basic auth, isole por `location` (ex.: `location /api/` sem auth, `location /` com auth) — ver Troubleshooting.

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

Causa mais comum: dummy certs nao criados.

#### Por que o compose usa `quay.io/minio/...` e nao `minio/...`?

A MinIO **removeu as imagens do Docker Hub** — o repo `minio/minio` nao existe mais la (a API do hub responde 404). Um `pull` da URL antiga falha com um erro enganoso:

```
pull access denied for minio/minio, repository does not exist or may require 'docker login'
```

Nao e falta de login nem rate limit: o repositorio sumiu mesmo. O Docker Hub responde "may require docker login" para QUALQUER repo inexistente (inclusive os privados), porque nao quer confirmar para qualquer um quais repos privados existem — existe e nao-existe viram a mesma resposta 404.

A distribuicao oficial passou para **Quay.io**: `quay.io/minio/minio` e `quay.io/minio/mc`, onde inclusive os tags `RELEASE.*` continuam publicados (o pin deste repo, `RELEASE.2024-12-18T13-15-44Z`, existe la). Mesma imagem, mesmo conteudo — so o endereco mudou. Repositorios clonados deste repo antes da correcao precisam de um `git pull` para atualizar compose e scripts.

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
# HTTP/2 200  (body vazio e esperado — health check)

curl -I https://minio-console.binaryten.com.br
# HTTP/2 200  (Console sem basic auth; se ainda houver 401, ver Troubleshooting)
```

No navegador: `https://minio-console.binaryten.com.br` → tela de login MinIO (root user / root password do `.env`).

> **Se aparecer "Not secure" mesmo com 200 no curl:** e cache do Chrome de quando o cert era dummy. Teste em **aba anonima** (`Ctrl+Shift+N`) — deve mostrar o cadeado verde. Se funcionar no anonimo, limpe o site: F12 → Application → Storage → Clear site data, ou `Ctrl+Shift+Delete` → "Cached images and files". Ver Troubleshooting.

> **`https://s3.binaryten.com.br/minio/health/live` sempre mostra tela branca** no navegador — e normal. O endpoint retorna `200` com body vazio. Use `curl -I` para confirmar.

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
2. Login com `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` do `.env`
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
docker run --rm --network vps-infra-internal --entrypoint /bin/sh quay.io/minio/mc:latest -c \
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
# Bucket dev (path-style, privado, via URL pre-assinada): https://s3.binaryten.com.br/odd-oddities-dev
```

### Prod

```env
MINIO_ACCESS_KEY=<access-key-prod>
MINIO_SECRET_KEY=<secret-key-prod>
MINIO_BUCKET_NAME=odd-oddities-prod
STORAGE_DOMAIN=s3.binaryten.com.br
# Bucket prod: https://s3.binaryten.com.br/odd-oddities-prod
```

O worker usa:

- `Endpoint=https://s3.binaryten.com.br` — upload/list
- `PublicEndpoint=https://s3.binaryten.com.br` — URL pre-assinada (Meta)
- Bucket dev link direto (path-style): `https://s3.binaryten.com.br/odd-oddities-dev/<objeto>` (requer URL pre-assinada, bucket privado)

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
| Clone: `Password authentication is not supported for Git operations` | Repo privado; o git nao aceita senha da conta via HTTPS | Usar a Opcao A da 4.1 (deploy key SSH) |
| `Permission denied (publickey)` no `ssh -T git@github.com` | Chave no perfil pessoal em vez das Deploy keys do repo, ou `~/.ssh/config` sem `IdentitiesOnly` | Revisar A2/A3/A4 da 4.1 |
| `pull access denied for minio/minio, repository does not exist` no compose up | Imagens MinIO nao existem mais no Docker Hub | compose/scripts ja apontam para `quay.io/minio/...` — `git pull` na VPS e repetir o 4.6 |
| `git pull` aborta: `Your local changes would be overwritten by merge` | VPS rodou `chmod +x`/`sed` antes do fix e a working tree ficou suja; o pull novo quer mudar os mesmos arquivos (agora com `quay.io` e `+x` rastreado) | **Transicao de quem ja rodou o 4.2 antes do fix:** `git checkout -- . && git pull` (descarta so o chmod/sed local, que o pull ja traz rastreado). Verifique `ls -l certbot/scripts/*.sh minio/init-buckets.sh` → `-rwxr-xr-x`. Depois `docker compose up -d minio nginx` |
| Nginx reinicia em loop, log `cannot load certificate` | Dummy certs nao criados | Rodar `bash certbot/scripts/create-dummy-certs.sh` e `docker compose up -d nginx` |
| `S3_DOMAIN is required` nos scripts | `.env` nao existe ou nao foi preenchido | `cp .env.example .env` e editar |
| `$'\r': command not found` | Scripts com CRLF do Windows | `sed -i 's/\r$//' certbot/scripts/*.sh minio/*.sh` |
| Certbot: connection refused / timeout | DNS errado, firewall ou Nginx fora | `dig +short s3.binaryten.com.br`; `sudo ufw status`; `docker compose ps` |
| Certbot: unauthorized / 404 no challenge | Volume ACME ou server_name | Conferir `S3_DOMAIN` no `.env` e `docker compose logs nginx` |
| Certificado do console nao existe | Um unico cert SAN nos dois dominios | Este repo emite **dois** certs. Use `init-cert.sh` atual |
| 502 Bad Gateway | MinIO nao healthy | `docker compose logs minio` |
| `mc` em `localhost:9000` falha de fora da VPS | Porta 9000 so escuta em 127.0.0.1 | Use o script `init-buckets.sh` ou `127.0.0.1` via SSH |
| Console branco apos login (`/api/v1/session 401`) | Duplo auth legado (`auth_basic` do Nginx sobre o Console) bloqueava o `fetch` do JS — Nginx retornava 401 antes do MinIO | **Removido neste repo:** `minio-console.conf.template` sem basic auth. `git pull` + `docker compose build nginx && docker compose up -d nginx`. Para reativar basic auth, isole por `location` (ver secao 4.4) |
| 401 no Console (versao antiga com htpasswd) | `.htpasswd` errado | Regenerar hash e recarregar Nginx — nao se aplica a versao atual sem basic auth |
| Navegador "Not secure" mas `curl -I` da 200 | Cache do Chrome do periodo com cert dummy | Testar em aba anonima (`Ctrl+Shift+N`). Se ok, limpar: F12 → Application → Storage → Clear site data |
| `https://s3.../minio/health/live` tela branca | Comportamento esperado | Health check retorna 200 com body vazio. Confirmar com `curl -I` |
| Upload S3 falha com redirect | Cliente usando `http://` | Endpoint do worker deve ser `https://s3.binaryten.com.br` |
| Let's Encrypt falha com IPv6 | Registro AAAA sem IPv6 na VPS | Remover AAAA na Hostinger |
| `error mounting .htpasswd` (legado) | Versao antiga exigia `.htpasswd` | Nao se aplica — versao atual nao monta `.htpasswd`. Remova a linha do volume se estiver em compose customizado |
| Worker na VPS nao alcança `s3.binaryten.com.br` | Hairpin NAT | No compose do app: `extra_hosts: ["s3.binaryten.com.br:host-gateway"]` |
| `Conflict: container name vps-certbot` | Container de um `run` anterior | `docker rm -f vps-certbot` e repetir o script |

---

## Referencias

- [Adicionar um novo servico (API/MVC) com HTTPS](./add-new-service.md)
- [Configuracao DNS na Hostinger](./hostinger-dns.md)
- [Gerenciamento de Buckets](./bucket-management.md)

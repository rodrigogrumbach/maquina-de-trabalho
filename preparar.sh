#!/usr/bin/env bash
# Máquina de trabalho da Brainstorming: prepara um Ubuntu 24.04 LTS recém-criado para trabalhar com o Claude pelas fichas
# do OC. Idempotente: rodar de novo só confere e completa o que falta. Nenhum segredo aqui: o login do Claude e do GitHub é feito pela
# pessoa no primeiro acesso (primeiro-acesso.sh) e a senha do Firebird de teste é gerada na própria máquina.
#
# Uso: sudo bash preparar.sh            (ou pelo cloud-init, que roda como root)
# Opções (variáveis de ambiente): USUARIO (padrão: trabalho), FUSO (padrão: America/Sao_Paulo), SEM_FIREBIRD=1, SEM_CLAUDE=1.
set -euo pipefail

USUARIO="${USUARIO:-trabalho}"
FUSO="${FUSO:-America/Sao_Paulo}"
LOG=/var/log/maquina-de-trabalho.log
PASTA=/opt/maquina-de-trabalho          # os roteiros ficam aqui (verificar.sh, primeiro-acesso.sh)
export DEBIAN_FRONTEND=noninteractive

passo() { echo "== $(date '+%F %T') · $*" | tee -a "$LOG"; }

[ "$(id -u)" -eq 0 ] || { echo "Rode como root: sudo bash $0"; exit 1; }
. /etc/os-release
[ "${ID:-}" = ubuntu ] || { echo "Este roteiro é para Ubuntu (24.04 LTS). No macOS, use preparar-macos.sh."; exit 1; }
[ "${VERSION_ID:-}" = "24.04" ] || passo "Aviso: feito para o Ubuntu 24.04; esta máquina é ${VERSION_ID:-?}. Seguindo."
touch "$LOG"; chmod 600 "$LOG"

# ---------------------------------------------------------------- sistema
passo "Fuso $FUSO e pacotes básicos (numa máquina nova, espera a atualização automática do primeiro boot terminar)"
timedatectl set-timezone "$FUSO" 2>/dev/null || ln -sf "/usr/share/zoneinfo/$FUSO" /etc/localtime
apt-get -o DPkg::Lock::Timeout=1800 update -q
apt-get -o DPkg::Lock::Timeout=1800 install -y -q ca-certificates curl gnupg git jq unzip ufw fail2ban unattended-upgrades apt-transport-https >>"$LOG"

passo "Atualizações automáticas de segurança"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# ---------------------------------------------------------------- a pessoa que trabalha
passo "Usuário $USUARIO"
if ! id "$USUARIO" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USUARIO" >>"$LOG"
fi
usermod -aG sudo "$USUARIO"
install -d -m 700 -o "$USUARIO" -g "$USUARIO" "/home/$USUARIO/.ssh" "/home/$USUARIO/Projetos"
# a chave SSH que a nuvem pôs no root (ou no usuário padrão da imagem) passa a valer também para a pessoa
for origem in /root/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys; do
  [ -s "$origem" ] || continue
  touch "/home/$USUARIO/.ssh/authorized_keys"
  while read -r linha; do
    [ -n "$linha" ] && ! grep -qxF "$linha" "/home/$USUARIO/.ssh/authorized_keys" && echo "$linha" >> "/home/$USUARIO/.ssh/authorized_keys"
  done < "$origem"
done
[ -f "/home/$USUARIO/.ssh/authorized_keys" ] && chown "$USUARIO:$USUARIO" "/home/$USUARIO/.ssh/authorized_keys" && chmod 600 "/home/$USUARIO/.ssh/authorized_keys"
# sudo sem senha (a conta não tem senha; o acesso é só pela chave)
echo "$USUARIO ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USUARIO"; chmod 440 "/etc/sudoers.d/90-$USUARIO"

# ---------------------------------------------------------------- SSH, firewall e fail2ban
passo "SSH só por chave"
if [ -s "/home/$USUARIO/.ssh/authorized_keys" ] || [ -s /root/.ssh/authorized_keys ]; then
  cat > /etc/ssh/sshd_config.d/10-brainstorming.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
  if sshd -t 2>>"$LOG"; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  else
    rm -f /etc/ssh/sshd_config.d/10-brainstorming.conf
    passo "ATENÇÃO: a configuração do SSH não passou no sshd -t; ficou como estava."
  fi
else
  passo "ATENÇÃO: nenhuma chave SSH na máquina — a senha do SSH NÃO foi desligada (para não trancar ninguém fora). Ponha a chave e rode de novo."
fi

passo "Firewall (só o SSH entra)"
ufw default deny incoming >>"$LOG"
ufw default allow outgoing >>"$LOG"
ufw allow OpenSSH >>"$LOG"
ufw --force enable >>"$LOG"

passo "fail2ban no SSH"
cat > /etc/fail2ban/jail.d/10-brainstorming.conf <<'EOF'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban >>"$LOG" 2>&1
systemctl restart fail2ban

# ---------------------------------------------------------------- Java, GitHub CLI e Docker (repositórios oficiais)
passo "Java (Temurin 25, o JDK dos projetos)"
install -d -m 755 /etc/apt/keyrings
[ -s /etc/apt/keyrings/adoptium.gpg ] || curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/adoptium.list

passo "GitHub CLI"
[ -s /etc/apt/keyrings/githubcli.gpg ] || curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg
chmod 644 /etc/apt/keyrings/githubcli.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list

passo "Docker"
[ -s /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod 644 /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

apt-get -o DPkg::Lock::Timeout=1800 update -q
apt-get -o DPkg::Lock::Timeout=1800 install -y -q temurin-25-jdk gh docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >>"$LOG"
# os logs dos contêineres limitados (não enchem o disco)
install -d -m 755 /etc/docker
if [ ! -s /etc/docker/daemon.json ] || ! grep -q max-size /etc/docker/daemon.json; then
  echo '{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }' > /etc/docker/daemon.json
  systemctl restart docker
fi
systemctl enable --now docker >>"$LOG" 2>&1
usermod -aG docker "$USUARIO"
# o journal também limitado
install -d /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/10-brainstorming.conf
systemctl restart systemd-journald

# ---------------------------------------------------------------- Firebird de teste (dialetos 1 e 3), só nesta máquina
if [ "${SEM_FIREBIRD:-0}" != 1 ]; then
  passo "Firebird 5 de teste em contêiner (só em 127.0.0.1)"
  install -d -m 750 -o root -g "$USUARIO" /etc/teste-local
  if [ ! -s /etc/teste-local/firebird-senha ]; then
    # gerada aqui, nunca escrita no log nem no roteiro; quem trabalha lê o arquivo (grupo da pessoa)
    head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20 > /etc/teste-local/firebird-senha
    chmod 640 /etc/teste-local/firebird-senha; chown root:"$USUARIO" /etc/teste-local/firebird-senha
  fi
  if ! docker inspect firebird-teste >/dev/null 2>&1; then
    docker run -d --name firebird-teste --restart unless-stopped -p 127.0.0.1:3050:3050 -v firebird-teste:/var/lib/firebird/data \
      -e FIREBIRD_ROOT_PASSWORD="$(cat /etc/teste-local/firebird-senha)" firebirdsql/firebird:5 >>"$LOG"
  fi
  docker start firebird-teste >/dev/null 2>&1 || true
  # um banco por dialeto (vazio, só para os testes); criado uma vez
  for d in 1 3; do
    if ! docker exec firebird-teste test -f "/var/lib/firebird/data/teste-d$d.fdb"; then
      for t in $(seq 1 30); do
        if printf "SET SQL DIALECT %s;\nCREATE DATABASE 'localhost:/var/lib/firebird/data/teste-d%s.fdb' DEFAULT CHARACTER SET UTF8;\nCOMMIT;\n" "$d" "$d" \
             | docker exec -i -e ISC_USER=SYSDBA -e ISC_PASSWORD="$(cat /etc/teste-local/firebird-senha)" firebird-teste /opt/firebird/bin/isql -q >/dev/null 2>&1; then break; fi
        sleep 2
      done
    fi
  done
fi

# ---------------------------------------------------------------- Claude Code (o instalador oficial, para a pessoa)
if [ "${SEM_CLAUDE:-0}" != 1 ]; then
  passo "Claude Code (instalador oficial, na conta de $USUARIO)"
  if [ ! -x "/home/$USUARIO/.local/bin/claude" ]; then
    su - "$USUARIO" -c 'curl -fsSL https://claude.ai/install.sh | bash' >>"$LOG" 2>&1 || passo "Aviso: o Claude Code não instalou agora; o verificar.sh aponta e dá para rodar de novo."
  fi
fi

# ---------------------------------------------------------------- serviços do usuário sem ninguém logado (EV-0141)
# o linger: um serviço do usuário (o que um projeto liga no primeiro acesso) fica no ar sem login e volta sozinho depois de reiniciar.
passo "Serviços do usuário sem login (linger)"
loginctl enable-linger "$USUARIO" >>"$LOG" 2>&1 || passo "Aviso: o linger não ligou; o primeiro acesso tenta de novo."

# ---------------------------------------------------------------- os roteiros do primeiro acesso e da conferência
passo "Roteiros em $PASTA"
install -d -m 755 "$PASTA"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in verificar.sh primeiro-acesso.sh; do
  [ -f "$AQUI/$f" ] && [ "$AQUI" != "$PASTA" ] && install -m 755 "$AQUI/$f" "$PASTA/$f"
done
ln -sf "$PASTA/primeiro-acesso.sh" /usr/local/bin/primeiro-acesso
ln -sf "$PASTA/verificar.sh" /usr/local/bin/maquina-pronta
# o aviso no login: enquanto o primeiro acesso não foi feito
cat > /etc/profile.d/90-maquina-de-trabalho.sh <<'EOF'
if [ "$(id -un)" != root ] && [ ! -f "$HOME/.maquina-primeiro-acesso" ]; then
  echo ""; echo "  Máquina de trabalho da Brainstorming: falta o primeiro acesso. Rode:  primeiro-acesso"; echo ""
fi
EOF

passo "Conferência"
USUARIO="$USUARIO" bash "$PASTA/verificar.sh" | tee -a "$LOG" || true
passo "Pronto. Entre como $USUARIO (ssh $USUARIO@<endereço>) e rode: primeiro-acesso"

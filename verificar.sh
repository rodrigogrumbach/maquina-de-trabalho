#!/usr/bin/env bash
# O relatório "máquina pronta": o que o preparar.sh deixou e o que falta, item a item (OK, FALTA ou DEPOIS — este só depois do
# primeiro acesso da pessoa). Só versões e situações: nenhuma senha, chave ou token. Grava também em /var/log/maquina-pronta.txt (root).
# Uso: maquina-pronta   (ou bash verificar.sh). Sai com 0 quando nada FALTA.
set -uo pipefail

USUARIO="${USUARIO:-${SUDO_USER:-$(id -un)}}"
[ "$USUARIO" = root ] && USUARIO=trabalho
CASA="/home/$USUARIO"
falta=0
saida=""

item() {   # item <situação> <o quê> <detalhe>
  local s="$1"; shift
  [ "$s" = FALTA ] && falta=$((falta + 1))
  saida+="$(printf '%-6s %-34s %s' "$s" "$1" "${2:-}")"$'\n'
}
ok_se() { if eval "$2" >/dev/null 2>&1; then item OK "$1" "${3:-}"; else item FALTA "$1" "${4:-}"; fi; }
versao() { "$@" 2>&1 | head -1 | tr -d '\r'; }

ok_se "Ubuntu" '. /etc/os-release && [ "$ID" = ubuntu ]' "$(. /etc/os-release; echo "$PRETTY_NAME")" "não é Ubuntu"
ok_se "Fuso America/Sao_Paulo" '[ "$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone)" = "${FUSO:-America/Sao_Paulo}" ]' "$(date '+%Z %z')"
ok_se "Atualizações de segurança" 'grep -q "Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades' "unattended-upgrades"
ok_se "Firewall ativo" 'ufw status 2>/dev/null | grep -q "Status: active" || sudo -n ufw status 2>/dev/null | grep -q "Status: active"' "só o SSH entra"
ok_se "SSH só por chave" 'grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config.d/10-brainstorming.conf' "" "senha do SSH ainda ligada: veja /var/log/maquina-de-trabalho.log"
ok_se "fail2ban (SSH)" 'systemctl is-active --quiet fail2ban'
ok_se "Usuário $USUARIO" "id $USUARIO" "" "não existe"
ok_se "Pasta de trabalho" "[ -d $CASA/Projetos ] && [ \"\$(stat -c %a $CASA/Projetos)\" = 700 ]" "$CASA/Projetos (só a pessoa)"
ok_se "Java" 'java -version' "$(versao java -version)"
ok_se "Git" 'git --version' "$(versao git --version)"
ok_se "GitHub CLI" 'gh --version' "$(versao gh --version)"
ok_se "Docker" 'docker info || sudo -n docker info' "$(versao docker --version)"
ok_se "Logs dos contêineres limitados" 'grep -q max-size /etc/docker/daemon.json' "10 MB × 3"
if [ "${SEM_FIREBIRD:-0}" != 1 ]; then
  fb='docker exec firebird-teste test -f /var/lib/firebird/data/teste-d1.fdb && docker exec firebird-teste test -f /var/lib/firebird/data/teste-d3.fdb'
  ok_se "Firebird de teste (dialetos 1 e 3)" "$fb || sudo -n sh -c '$fb'" "127.0.0.1:3050; senha em /etc/teste-local/firebird-senha"
fi
ok_se "Claude Code" "[ -x $CASA/.local/bin/claude ]" "$(versao "$CASA/.local/bin/claude" --version 2>/dev/null)" "rode de novo o preparar.sh"

# depois do primeiro acesso (login da pessoa e os repositórios)
if [ -f "$CASA/.maquina-primeiro-acesso" ]; then
  # na conta da pessoa (o preparar.sh roda este relatório como root): o login e a compilação são dela
  if [ "$(id -u)" -eq 0 ]; then como() { sudo -n -u "$USUARIO" -H "$@"; }; else como() { "$@"; }; fi
  ok_se "Login no Claude" "como $CASA/.local/bin/claude auth status"
  ok_se "Login no GitHub" "como gh auth status"
  # o projeto da compilação curta: escolhido no primeiro acesso (~/.maquina-compilar: a pasta e, na linha 2, os argumentos do mvnw).
  # O mvnw vem do Git muitas vezes sem a permissão de execução (repositório criado no Windows): roda com o sh, e basta existir.
  projeto="$(sed -n 1p "$CASA/.maquina-compilar" 2>/dev/null)"; args="$(sed -n 2p "$CASA/.maquina-compilar" 2>/dev/null)"
  if [ -n "$projeto" ] && [ -f "$projeto/mvnw" ]; then
    if (cd "$projeto" && como timeout 900 sh ./mvnw -B -q -ntp ${args:--DskipTests compile}) >/tmp/maquina-compilacao.log 2>&1; then
      item OK "Compilação curta" "$(basename "$projeto") compila"
    else
      item FALTA "Compilação curta" "$(basename "$projeto"): veja /tmp/maquina-compilacao.log"
    fi
  else
    item DEPOIS "Compilação curta" "nenhum projeto com mvnw escolhido no primeiro acesso"
  fi
  # EV-0141: as credenciais do Maven só da pessoa, e as conferências próprias de cada projeto clonado (o arquivo
  # instalacao/maquina-de-trabalho/na-verificacao.sh do projeto, rodado na conta da pessoa, escreve linhas "OK|FALTA|DEPOIS<tab>item<tab>detalhe")
  [ -f "$CASA/.m2/settings.xml" ] && ok_se "Credenciais do Maven" "[ \"\$(stat -c %a $CASA/.m2/settings.xml)\" = 600 ]" "só a pessoa lê (600)" "o settings.xml tem de ter a permissão 600"
  for conf in "$CASA"/Projetos/*/instalacao/maquina-de-trabalho/na-verificacao.sh; do
    [ -f "$conf" ] || continue
    while IFS=$'\t' read -r s o d; do
      case "$s" in OK|FALTA|DEPOIS) item "$s" "$o" "$d";; esac
    done < <(como env XDG_RUNTIME_DIR="/run/user/$(id -u "$USUARIO")" bash "$conf" 2>/dev/null)
  done
else
  item DEPOIS "Login no Claude e no GitHub" "a pessoa faz no primeiro acesso (primeiro-acesso)"
  item DEPOIS "Compilação curta" "depois do primeiro acesso"
fi

relatorio="Máquina de trabalho · $(hostname) · $(date '+%d/%m/%Y %H:%M')"$'\n'"$saida"
if [ "$falta" -eq 0 ]; then relatorio+="RESULTADO: máquina pronta"$'\n'; else relatorio+="RESULTADO: faltam $falta item(ns)"$'\n'; fi
printf '%s' "$relatorio"
[ "$(id -u)" -eq 0 ] && { printf '%s' "$relatorio" > /var/log/maquina-pronta.txt; chmod 644 /var/log/maquina-pronta.txt; }
[ "$falta" -eq 0 ]

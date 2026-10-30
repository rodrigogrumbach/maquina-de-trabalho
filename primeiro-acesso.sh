#!/usr/bin/env bash
# O primeiro acesso, guiado, na conta da pessoa (EV-0125; EV-0141: a máquina pronta em 2 passos — o cloud-init e este roteiro):
#   1. entrar no Claude e no GitHub (a própria pessoa, no navegador; o GitHub já com a leitura dos pacotes, read:packages);
#   2. a identidade do Git (a da conta do GitHub, com o e-mail noreply);
#   3. os repositórios: os de CLONAR (dono/nome separados por espaço; vêm no comando que a tela de quem gerencia a máquina mostra) e os
#      escolhidos na lista dos que a conta da pessoa enxerga;
#   4. os passos próprios de cada projeto clonado: o arquivo instalacao/maquina-de-trabalho/no-primeiro-acesso.sh do projeto, se ele
#      trouxer (é o projeto, e não este roteiro público, que sabe o que precisa: credenciais do Maven, agente, pareamento...);
#   5. conferir (o relatório "máquina pronta").
# Pode rodar de novo: o que já está feito é pulado (nada é duplicado). Nenhum segredo aparece na tela, no log ou no Git.
set -uo pipefail

[ "$(id -u)" -ne 0 ] || { echo "Rode na sua conta (não como root): primeiro-acesso"; exit 1; }
CLAUDE="$HOME/.local/bin/claude"
PROJETOS="$HOME/Projetos"

# o MAQUINA e o CLONAR que a gestão da máquina deixou (~/.config/maquina-de-trabalho/ambiente), quando não vieram no comando. Só essas
# duas linhas, conferidas (nada do arquivo é executado).
AMB="$HOME/.config/maquina-de-trabalho/ambiente"
if [ -f "$AMB" ]; then
  v="$(sed -n 's/^MAQUINA=\([[:alnum:]._-]\{1,40\}\)$/\1/p' "$AMB" | head -1)"; [ -z "${MAQUINA:-}" ] && [ -n "$v" ] && export MAQUINA="$v"
  v="$(sed -n 's#^CLONAR=\([A-Za-z0-9._/ -]\{1,400\}\)$#\1#p' "$AMB" | head -1)"; [ -z "${CLONAR:-}" ] && [ -n "$v" ] && export CLONAR="$v"
fi

# a etapa em que o roteiro está (uma palavra, sem segredo), para quem gerencia a máquina mostrar a dica do momento
etapa() { mkdir -p "$HOME/.config/maquina-de-trabalho" && printf '%s\n' "$1" > "$HOME/.config/maquina-de-trabalho/etapa"; }

echo ""
echo "  Primeiro acesso à máquina de trabalho da Brainstorming"
echo "  ------------------------------------------------------"
echo "  1. Claude e GitHub   2. Git   3. Repositórios   4. Passos dos projetos   5. Conferir"
echo ""

# ---------------------------------------------------------------- 1. Claude e GitHub
etapa claude
if [ -x "$CLAUDE" ] && "$CLAUDE" auth status >/dev/null 2>&1; then
  echo "✓ 1. Claude: já entrou."
else
  echo "→ 1. Entrar no Claude: abre um endereço para você entrar com a sua conta."
  "$CLAUDE" auth login || { echo "  Não entrou no Claude. Rode primeiro-acesso de novo quando quiser."; exit 1; }
fi

# o GitHub por HTTPS, pelo navegador; o gh guarda a credencial dele (este roteiro não vê). O read:packages deixa o Maven ler pacotes
# publicados no GitHub Packages.
etapa github
# o código de uso único do GitHub (XXXX-XXXX) vai também para um arquivo da conta, enquanto o login está aberto, para quem gerencia a
# máquina mostrá-lo com Copiar (não é segredo: vence em minutos e só autoriza esta máquina na conta de quem o digitar); apagado ao sair
CODIGO_GH="$HOME/.config/maquina-de-trabalho/codigo-github"
com_codigo() {   # com_codigo <comando do gh…>: roda mostrando tudo e guarda o código que aparecer
  local log; log="$(mktemp)"; chmod 600 "$log"
  ( umask 077; for _ in $(seq 1 600); do c="$(grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' "$log" 2>/dev/null | tail -1)"; [ -n "$c" ] && { printf '%s\n' "$c" > "$CODIGO_GH"; chmod 600 "$CODIGO_GH"; break; }; sleep 1; done ) &
  local vigia=$!
  "$@" 2> >(tee -a "$log" >&2); local r=$?
  kill "$vigia" 2>/dev/null; rm -f "$log" "$CODIGO_GH"
  return $r
}
if gh auth status >/dev/null 2>&1; then
  echo "✓ 1. GitHub: já entrou."
else
  echo "→ 1. Entrar no GitHub: escolha GitHub.com, HTTPS e o navegador (ou o código de uso único)."
  com_codigo gh auth login --hostname github.com --git-protocol https --web --scopes read:packages || { echo "  Não entrou no GitHub. Rode primeiro-acesso de novo."; exit 1; }
fi
if ! gh auth status 2>&1 | grep -q "read:packages"; then
  echo "→ 1. Falta ao GitHub a permissão de ler os pacotes (read:packages): o navegador pede a confirmação."
  com_codigo gh auth refresh --hostname github.com --scopes read:packages || echo "  · Sem o read:packages, projetos que leem pacotes do GitHub não compilam. Rode primeiro-acesso de novo."
fi
gh auth setup-git >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 2. a identidade do Git (a que já existe fica)
etapa git
if [ -z "$(git config --global user.name 2>/dev/null)" ] || [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  login="$(gh api user --jq .login 2>/dev/null)"; gid="$(gh api user --jq .id 2>/dev/null)"; nome="$(gh api user --jq '.name // .login' 2>/dev/null)"
  if [ -n "$login" ] && [ -n "$gid" ]; then
    git config --global user.name "$nome"; git config --global user.email "$gid+$login@users.noreply.github.com"
    echo "✓ 2. Git: commits como $nome (e-mail noreply do GitHub)."
  else
    echo "· 2. Git: sem o login do GitHub, a identidade fica para a próxima vez."
  fi
else
  echo "✓ 2. Git: já tem a identidade ($(git config --global user.name))."
fi

# ---------------------------------------------------------------- 3. os repositórios
etapa repositorios
mkdir -p "$PROJETOS"; chmod 700 "$PROJETOS"
clonar() {   # clonar <dono/nome>
  local destino="$PROJETOS/${1##*/}"
  if [ -d "$destino/.git" ]; then echo "   ✓ $1: já clonado em $destino"; return 0; fi
  gh repo clone "$1" "$destino" -- -q && echo "   ✓ $1 → $destino" && { [ -f "$destino/mvnw" ] && chmod +x "$destino/mvnw"; true; }
}
for r in ${CLONAR:-}; do
  [[ "$r" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "   · $r: não é dono/nome"; continue; }
  clonar "$r"
done
# com CLONAR informado, a lista vem pronta: não pergunta (para clonar outro depois: gh repo clone dono/nome ~/Projetos/nome)
repos=()
[ -n "${CLONAR:-}" ] || mapfile -t repos < <( { gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner'
                        for org in $(gh api user/orgs --jq '.[].login' 2>/dev/null); do gh repo list "$org" --limit 200 --json nameWithOwner --jq '.[].nameWithOwner'; done; } 2>/dev/null | sort -u)
if [ -n "${CLONAR:-}" ]; then
  echo "✓ 3. Repositórios: os de CLONAR."
elif [ "${#repos[@]}" -eq 0 ]; then
  echo "· 3. A sua conta do GitHub não enxerga nenhum repositório (ou a lista não veio). Clone depois com: gh repo clone dono/nome ~/Projetos/nome"
else
  echo "→ 3. Repositórios que a sua conta enxerga:"
  for i in "${!repos[@]}"; do
    nome="${repos[$i]##*/}"; marca=" "; [ -d "$PROJETOS/$nome/.git" ] && marca="✓"
    printf '   %3d %s %s\n' "$((i + 1))" "$marca" "${repos[$i]}"
  done
  read -r -p "   Quais clonar? (números separados por espaço; Enter = nenhum a mais): " escolha
  for n in $escolha; do
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#repos[@]}" ] || { echo "   · $n: não é um número da lista"; continue; }
    clonar "${repos[$((n - 1))]}"
  done
fi

# a compilação curta da conferência: um dos projetos clonados que tem o mvnw (fica em ~/.maquina-compilar). Com CLONAR informado, sem
# perguntar: o 1º de CLONAR que tem o mvnw (senão o 1º da pasta), com os argumentos padrão
mapfile -t comMvnw < <(find "$PROJETOS" -mindepth 2 -maxdepth 2 -name mvnw -printf '%h\n' 2>/dev/null | sort)
if [ "${#comMvnw[@]}" -gt 0 ] && [ ! -s "$HOME/.maquina-compilar" ] && [ -n "${CLONAR:-}" ]; then
  escolhido=""
  for r in $CLONAR; do [ -f "$PROJETOS/${r##*/}/mvnw" ] && { escolhido="$PROJETOS/${r##*/}"; break; }; done
  printf '%s\n%s\n' "${escolhido:-${comMvnw[0]}}" "" > "$HOME/.maquina-compilar"
  echo "✓ Compilação curta da conferência: $(basename "${escolhido:-${comMvnw[0]}}")"
elif [ "${#comMvnw[@]}" -gt 0 ] && [ ! -s "$HOME/.maquina-compilar" ]; then
  echo "→ Projeto para a compilação curta da conferência:"
  for i in "${!comMvnw[@]}"; do printf '   %3d %s\n' "$((i + 1))" "${comMvnw[$i]}"; done
  read -r -p "   Qual? (número; Enter = o 1): " n; n="${n:-1}"
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#comMvnw[@]}" ]; then
    read -r -p "   Argumentos do mvnw (Enter = -DskipTests compile): " args
    printf '%s\n%s\n' "${comMvnw[$((n - 1))]}" "$args" > "$HOME/.maquina-compilar"
  fi
fi

# ---------------------------------------------------------------- 4. os passos próprios dos projetos clonados
etapa projetos
achou=0
for passo in "$PROJETOS"/*/instalacao/maquina-de-trabalho/no-primeiro-acesso.sh; do
  [ -f "$passo" ] || continue
  achou=1
  projeto="$(basename "$(dirname "$(dirname "$(dirname "$passo")")")")"
  echo "→ 4. Passos de $projeto:"
  PROJETOS="$PROJETOS" bash "$passo" || echo "   · os passos de $projeto não terminaram: rode primeiro-acesso de novo"
done
[ "$achou" = 1 ] || echo "· 4. Nenhum projeto clonado traz passos próprios."

etapa conferir
touch "$HOME/.maquina-primeiro-acesso"
echo ""
echo "→ 5. Conferindo (inclui a compilação curta, alguns minutos):"
if sudo -n true 2>/dev/null; then sudo -n maquina-pronta; else maquina-pronta; fi || true   # como root: o relatório em /var/log é o que o OC lê
echo ""
etapa fim
echo "Para trabalhar:  cd ~/Projetos/<projeto> && claude"

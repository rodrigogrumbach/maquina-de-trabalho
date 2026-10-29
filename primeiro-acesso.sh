#!/usr/bin/env bash
# O primeiro acesso, guiado, na conta da pessoa: entrar no Claude e no GitHub (a própria pessoa digita, no navegador; nada é
# guardado por este roteiro), escolher quais repositórios clonar — entre os que a conta do GitHub dela enxerga — e conferir. O
# pareamento com o OC (código de uso único) vem com a etapa 2 (agente) e por enquanto fica desligado. Pode rodar de novo: o que já está
# feito é pulado.
set -uo pipefail

[ "$(id -u)" -ne 0 ] || { echo "Rode na sua conta (não como root): primeiro-acesso"; exit 1; }
CLAUDE="$HOME/.local/bin/claude"
PAREAR=0   # etapa 2 (agente do OC): ainda não existe

echo ""
echo "  Primeiro acesso à máquina de trabalho da Brainstorming"
echo "  ------------------------------------------------------"
echo "  1. Entrar no Claude   2. Entrar no GitHub   3. Escolher e clonar os repositórios   4. Conferir"
echo ""

# 1. Claude
if [ -x "$CLAUDE" ] && "$CLAUDE" auth status >/dev/null 2>&1; then
  echo "✓ 1. Claude: já entrou."
else
  echo "→ 1. Entrar no Claude: abre um endereço para você entrar com a sua conta."
  "$CLAUDE" auth login || { echo "  Não entrou no Claude. Rode primeiro-acesso de novo quando quiser."; exit 1; }
fi

# 2. GitHub (HTTPS, pelo navegador; o gh guarda a credencial dele, este roteiro não vê)
if gh auth status >/dev/null 2>&1; then
  echo "✓ 2. GitHub: já entrou."
else
  echo "→ 2. Entrar no GitHub: escolha GitHub.com, HTTPS e o navegador (ou o código de uso único)."
  gh auth login --hostname github.com --git-protocol https --web || { echo "  Não entrou no GitHub. Rode primeiro-acesso de novo."; exit 1; }
fi
gh auth setup-git >/dev/null 2>&1 || true

# 3. os repositórios: a lista vem da própria conta da pessoa (os dela e os das organizações de que ela faz parte)
mkdir -p "$HOME/Projetos"; chmod 700 "$HOME/Projetos"
mapfile -t repos < <( { gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner'
                        for org in $(gh api user/orgs --jq '.[].login' 2>/dev/null); do gh repo list "$org" --limit 200 --json nameWithOwner --jq '.[].nameWithOwner'; done; } 2>/dev/null | sort -u)
if [ "${#repos[@]}" -eq 0 ]; then
  echo "· 3. A sua conta do GitHub não enxerga nenhum repositório (ou a lista não veio). Clone depois com: gh repo clone dono/nome ~/Projetos/nome"
else
  echo "→ 3. Repositórios que a sua conta enxerga:"
  for i in "${!repos[@]}"; do
    nome="${repos[$i]##*/}"; marca=" "; [ -d "$HOME/Projetos/$nome/.git" ] && marca="✓"
    printf '   %3d %s %s\n' "$((i + 1))" "$marca" "${repos[$i]}"
  done
  read -r -p "   Quais clonar? (números separados por espaço; Enter = nenhum): " escolha
  for n in $escolha; do
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#repos[@]}" ] || { echo "   · $n: não é um número da lista"; continue; }
    repo="${repos[$((n - 1))]}"; destino="$HOME/Projetos/${repo##*/}"
    if [ -d "$destino/.git" ]; then echo "   ✓ $repo: já clonado em $destino"; continue; fi
    gh repo clone "$repo" "$destino" -- -q && echo "   ✓ $repo → $destino"
  done
fi

# a compilação curta da conferência: um dos projetos clonados que tem o mvnw (a pessoa escolhe; fica em ~/.maquina-compilar)
mapfile -t comMvnw < <(find "$HOME/Projetos" -mindepth 2 -maxdepth 2 -name mvnw -printf '%h\n' 2>/dev/null | sort)
if [ "${#comMvnw[@]}" -gt 0 ] && [ ! -s "$HOME/.maquina-compilar" ]; then
  echo "→ Projeto para a compilação curta da conferência:"
  for i in "${!comMvnw[@]}"; do printf '   %3d %s\n' "$((i + 1))" "${comMvnw[$i]}"; done
  read -r -p "   Qual? (número; Enter = o 1): " n; n="${n:-1}"
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#comMvnw[@]}" ]; then
    read -r -p "   Argumentos do mvnw (Enter = -DskipTests compile): " args
    printf '%s\n%s\n' "${comMvnw[$((n - 1))]}" "$args" > "$HOME/.maquina-compilar"
  fi
fi

# 4. pareamento com o OC (etapa 2) — previsto, desligado
if [ "$PAREAR" = 1 ]; then echo "→ Parear com o OC: (etapa 2)"; else echo "· Pareamento com o OC: vem com a etapa 2 (agente)."; fi

touch "$HOME/.maquina-primeiro-acesso"
echo ""
echo "→ 4. Conferindo (inclui a compilação curta, alguns minutos):"
maquina-pronta || true
echo ""
echo "Para trabalhar:  cd ~/Projetos/<projeto> && claude"

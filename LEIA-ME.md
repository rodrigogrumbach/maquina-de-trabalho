# Máquina de trabalho

Roteiros que preparam um Ubuntu 24.04 LTS recém-criado para trabalhar com o Claude Code:
- **segurança:** atualizações automáticas de segurança, firewall (só o SSH entra), SSH só por chave e fail2ban;
- **ferramentas:** fuso America/Sao_Paulo, Java (Temurin 25), Git, GitHub CLI, Docker com logs limitados e o Claude Code;
- **testes:** um Firebird 5 de teste em contêiner, só na própria máquina.

**Não há segredo aqui.** O login do Claude e do GitHub é feito pela própria pessoa no primeiro acesso, e a senha do Firebird de teste
é gerada na máquina.

- `preparar.sh` — instala e configura. Idempotente: rodar de novo só confere e completa. Uso: `sudo bash preparar.sh`.
- `verificar.sh` — o relatório "máquina pronta" (comando `maquina-pronta`).
- `primeiro-acesso.sh` — o primeiro acesso guiado (comando `primeiro-acesso`): entrar no Claude e no GitHub, escolher quais repositórios
  clonar entre os que a sua conta enxerga, e conferir.

Numa VPS, o cloud-init baixa estes arquivos num commit fixo e confere o SHA-256 de cada um antes de rodar.

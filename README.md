# claude-statusline

Status line para o [Claude Code](https://claude.com/claude-code), em bash, com barra de contexto colorida e contagem regressiva do limite de 5h.

```
Test | 42% ████████▒▒▒▒▒▒▒▒▒▒▒▒ | 70% resets in 02:15, at 11:30
sources | feat-x | ✓ | +12 -3
```

## O que mostra

**Linha 1**
- Modelo.
- Uso do contexto em % com barra de 20 caracteres.
- Uso do limite de 5h em % e `resets in HH:mm, at HH:mm`: tempo restante e horário exato (local) do reset.

**Linha 2**
- Diretório atual (usa `cwd` se `workspace.current_dir` não existir).
- Branch e marcador `✓` (limpo) / `✗` (alterações), sempre que o diretório está em um repositório git (em HEAD destacado mostra o SHA curto).
- Linhas adicionadas (`+`) e removidas (`-`).

Campos ausentes são omitidos, sem separadores `|` sobrando.

### Cores por faixa de uso

| Uso | Cor |
|---|---|
| 0–25% | verde |
| 26–50% | amarelo |
| 51–75% | laranja |
| 76–100% | vermelho |

## Instalação

Requisitos: `bash` e `git`. Para editar o `settings.json` o instalador usa `jq` ou `node`; sem nenhum dos dois, ele imprime a linha para você adicionar manualmente.

```bash
bash install.sh
```

Depois reinicie o Claude Code.

O `install.sh` é autocontido (o script do status line está embutido nele) e:

1. grava `~/.claude/statusline.sh` (removendo `\r`, caso o arquivo tenha vindo com CRLF);
2. faz backup de `~/.claude/settings.json` em `settings.json.bak`;
3. define `statusLine` preservando as outras chaves.

### Windows

O Claude Code no Windows exige o [Git for Windows](https://git-scm.com), então basta rodar `bash install.sh` no **Git Bash**. Nesse ambiente o comando gravado é `bash ~/.claude/statusline.sh`. Em WSL funciona como no Linux.

### Instalação via Claude

Em qualquer ambiente, peça ao Claude Code: *"Siga as instruções de `statusline-prompt.md`"*. O arquivo tem as instruções e o script completo.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `install.sh` | Instalador autocontido (Linux, macOS, WSL, Git Bash). |
| `statusline-prompt.md` | Prompt para o Claude configurar o status line. |

## Testar manualmente

```bash
echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":42}}' | bash ~/.claude/statusline.sh
```

## Observação

O caminho do Windows (Git Bash) foi testado apenas por simulação em Linux.

#!/usr/bin/env bash
# Self-contained installer for the Claude Code status line.
# Works on Linux, macOS, WSL and Windows (Git Bash / MSYS / Cygwin).
# Uses jq or node to edit settings.json; without either it prints the snippet to add by hand.
set -euo pipefail
dest="$HOME/.claude"; settings="$dest/settings.json"
case "${INSTALL_UNAME:-$(uname -s)}" in
  MINGW*|MSYS*|CYGWIN*) cmd="bash ~/.claude/statusline.sh" ;;
  *)                    cmd="$dest/statusline.sh" ;;
esac

mkdir -p "$dest"
tr -d '\r' > "$dest/statusline.sh" <<'EOF_STATUSLINE'
#!/usr/bin/env bash
set -u
INPUT="$(cat)"
export INPUT_JSON="$INPUT"

# Terminal width for flex-spacer math. Honors STATUSLINE_COLS env override
# (used by parity tests); otherwise tries tput, finally falls back to 80.
STATUSLINE_COLS=${STATUSLINE_COLS:-$(tput cols 2>/dev/null || echo 80)}

# Visible-character length: strip CSI SGR sequences then count chars.
# Wide glyphs (emoji, CJK) count as 1 column — same simplification as the
# interpret backend uses.
__visible_len() {
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' | awk '{ printf "%s", length($0) }'
}

__repeat_char() {
  local ch="$1" n="$2" out=""
  if [ "$n" -le 0 ]; then printf ''; return; fi
  local i=0
  while [ "$i" -lt "$n" ]; do out+="$ch"; i=$((i+1)); done
  printf '%s' "$out"
}

__sgr() { printf '\033[%sm' "$1"; }
__reset() { printf '\033[0m'; }

if command -v jq >/dev/null 2>&1; then
  __field() {
    printf '%s' "$INPUT_JSON" | jq -r --arg p "$1" '
      ($p | split(".")) as $parts
      | reduce $parts[] as $k (.; if type == "object" and has($k) then .[$k] else null end)
      | if . == null then "" else (if type == "string" then . else tostring end) end
    ' 2>/dev/null
  }
else
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    __PY=python3
  elif command -v python >/dev/null 2>&1; then
    __PY=python
  else
    __PY=""
  fi
  __field() {
    if [ -z "$__PY" ]; then printf ''; return; fi
    PATH_ARG="$1" "$__PY" - <<'PYEOF' 2>/dev/null
import json, os
d = json.loads(os.environ.get('INPUT_JSON','{}') or '{}')
p = os.environ.get('PATH_ARG','')
cur = d
for part in p.split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None
        break
if cur is None:
    print('', end='')
elif isinstance(cur, bool):
    print('true' if cur else 'false', end='')
else:
    print(cur, end='')
PYEOF
  }
fi

__basename() { local s="$1"; printf '%s' "${s##*/}"; }
__compact() {
  local s="$1"
  if [ -z "$s" ]; then printf ''; return; fi
  # Use awk so we don't depend on bash arrays. Split on '/', take the first
  # char of every segment except the last; preserve a leading slash by
  # emitting an empty initial element when the path starts with '/'.
  printf '%s' "$s" | awk 'BEGIN{FS="/"} {
    out=""
    for (i=1; i<=NF; i++) {
      if (i==NF) { piece = $i }
      else if ($i == "") { piece = "" }
      else { piece = substr($i, 1, 1) }
      if (i==1) { out = piece } else { out = out "/" piece }
    }
    printf "%s", out
  }'
}
__tildify() {
  local s="$1"
  local home="${HOME%/}"
  if [ -n "$home" ] && [[ "$s" == "$home"* ]]; then
    printf '~%s' "${s#$home}"
    return
  fi
  if [[ "$s" =~ ^/(Users|home)/[^/]+(.*)$ ]]; then
    printf '~%s' "${BASH_REMATCH[2]}"
    return
  fi
  printf '%s' "$s"
}
__truncate() {
  local s="$1" n="$2"
  if [ "$n" -le 0 ] || [ "${#s}" -le "$n" ]; then printf '%s' "$s"; return; fi
  if [ "$n" -le 1 ]; then printf '%s' "${s:0:$n}"; return; fi
  printf '%s…' "${s:0:$((n-1))}"
}
__cost_fmt() { printf '$%.*f' "$2" "$1"; }
__dur_hms() {
  local ms="$1" total h m s
  total=$((ms/1000)); h=$((total/3600)); m=$(((total%3600)/60)); s=$((total%60))
  if [ "$h" -gt 0 ]; then printf '%d:%02d:%02d' "$h" "$m" "$s"
  else printf '%d:%02d' "$m" "$s"; fi
}
__dur_human() {
  local ms="$1" total m s h mm
  total=$((ms/1000))
  if [ "$total" -lt 60 ]; then printf '%ds' "$total"; return; fi
  m=$((total/60)); s=$((total%60))
  if [ "$m" -lt 60 ]; then
    if [ "$s" -gt 0 ]; then printf '%dm %ds' "$m" "$s"; else printf '%dm' "$m"; fi
    return
  fi
  h=$((m/60)); mm=$((m%60))
  if [ "$mm" -gt 0 ]; then printf '%dh %dm' "$h" "$mm"; else printf '%dh' "$h"; fi
}
__bar() {
  local pct="$1" width="$2" filled="$3" empty="$4"
  local p i n=0 e=0
  p="$(__norm_int "$pct")"
  if [ "$p" -gt 100 ]; then p=100; fi
  n=$(( (p * width + 50) / 100 ))
  e=$((width - n))
  local out=""
  for ((i=0; i<n; i++)); do out+="$filled"; done
  for ((i=0; i<e; i++)); do out+="$empty"; done
  printf '%s' "$out"
}
__git_branch() {
  local cwd dir
  cwd="$(__field workspace.current_dir)"
  if [ -z "$cwd" ]; then cwd="$(__field cwd)"; fi
  if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null
  else
    __field workspace.git_worktree
  fi
}
__git_dirty() {
  local cwd
  cwd="$(__field workspace.current_dir)"
  if [ -z "$cwd" ]; then cwd="$(__field cwd)"; fi
  if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then printf '1'; else printf '0'; fi
  else
    printf '0'
  fi
}
__emit() {
  local style="$1" text="$2"
  if [ -n "$style" ]; then __sgr "$style"; fi
  printf '%s' "$text"
  if [ -n "$style" ]; then __reset; fi
}
__norm_int() {
  # Coerce a possibly-decimal/empty/garbage field value to a non-negative
  # integer string. Used by token-display helpers.
  local v="$1"
  v="${v%%.*}"
  case "$v" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$v" ;;
  esac
}
__fmt_token_compact() {
  local n
  n="$(__norm_int "$1")"
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"; return; fi
  if [ "$n" -lt 1000000 ]; then
    local whole=$((n / 1000))
    local rem=$((n - whole * 1000))
    local dec=$((rem / 100))
    if [ "$dec" -eq 0 ]; then printf '%dk' "$whole"; else printf '%d.%dk' "$whole" "$dec"; fi
    return
  fi
  local whole=$((n / 1000000))
  local rem=$((n - whole * 1000000))
  local dec=$((rem / 100000))
  if [ "$dec" -eq 0 ]; then printf '%dM' "$whole"; else printf '%d.%dM' "$whole" "$dec"; fi
}
__fmt_token_full() {
  local n
  n="$(__norm_int "$1")"
  printf '%s' "$n" | awk '{
    s=$0; out=""; n=length(s)
    while (n > 3) { out=","substr(s,n-2,3) out; n -= 3 }
    out=substr(s,1,n) out
    printf "%s", out
  }'
}
__tokens_used() { __field 'context_window.total_input_tokens'; }
__tokens_total() { __field 'context_window.context_window_size'; }
__tokens_remaining() {
  local u t
  u="$(__norm_int "$(__tokens_used)")"
  t="$(__norm_int "$(__tokens_total)")"
  local r=$((t - u))
  if [ "$r" -lt 0 ]; then r=0; fi
  printf '%d' "$r"
}
__tokens_pct_int() {
  local p="$(__field 'context_window.used_percentage')"
  __norm_int "$p"
}
__tick() {
  if [ -n "${STATUSLINE_CLOCK_OVERRIDE:-}" ]; then
    printf '%s' "$STATUSLINE_CLOCK_OVERRIDE"
  else
    date +%s
  fi
}
__rel_time() {
  local target="$1"
  if [ -z "$target" ]; then printf ''; return; fi
  case "$target" in
    ''|*[!0-9.-]*) printf ''; return ;;
  esac
  local t_int="${target%.*}"
  if [ -z "$t_int" ] || [ "$t_int" = "-" ]; then printf ''; return; fi
  local now diff h m s rem
  now=$(__tick)
  diff=$((t_int - now))
  if [ "$diff" -le 0 ]; then printf ''; return; fi
  h=$((diff/3600)); rem=$(((diff%3600)/60))
  printf 'resets in %02d:%02d, at %s' "$h" "$rem" "$(date -d "@$t_int" +%H:%M 2>/dev/null)"
}
# Color for a usage percentage: green 0-25, yellow 26-50, orange 51-75, red 76-100.
__pct_color() {
  local p
  p="$(__norm_int "$1")"
  if [ "$p" -le 25 ]; then printf '38;2;166;227;161'
  elif [ "$p" -le 50 ]; then printf '38;2;249;226;175'
  elif [ "$p" -le 75 ]; then printf '38;2;250;179;135'
  else printf '38;2;243;139;168'; fi
}

# Separator is emitted only between segments that actually have content.
__first=1
__sep() {
  if [ "$__first" -eq 0 ]; then __emit '' ' | '; fi
  __first=0
}

# ---- Line 1 ----
if [ "$(__field 'fast_mode')" = 'true' ]; then
  __sep; __emit '38;2;205;214;244' '⚡fast'
fi
__v="$(__field 'model.display_name')"
if [ -n "$__v" ]; then
  __sep; __emit '38;2;203;166;247' "$__v"
fi
if [ "$(__field 'thinking.enabled')" = 'true' ]; then
  __v="$(__field 'effort.level')"
  if [ -n "$__v" ]; then
    __sep; __emit '38;2;205;214;244' "$__v"
  fi
fi
__v="$(__field 'context_window.used_percentage')"
if [ -n "$__v" ]; then
  __col="$(__pct_color "$__v")"
  __sep
  __emit "$__col" "$(__norm_int "$__v")%"
  printf ' '
  __emit "$__col" "$(__bar "$__v" 20 '█' '▒')"
fi
__v="$(__field 'rate_limits.five_hour.used_percentage')"
if [ -n "$__v" ]; then
  __sep
  __col="$(__pct_color "$__v")"
  __emit "$__col" "$(__norm_int "$__v")%"
  __out="$(__rel_time "$(__field 'rate_limits.five_hour.resets_at')")"
  if [ -n "$__out" ]; then printf ' '; __emit '' "$__out"; fi
fi
__reset
printf '\n'

# ---- Line 2 ----
__first=1
__wt="$(__field 'workspace.git_worktree')"
__v="$(__field 'workspace.current_dir')"
[ -z "$__v" ] && __v="$(__field 'cwd')"
__v="$(__basename "$__v")"
if [ -n "$__v" ]; then
  __sep; __emit '38;2;137;180;250' "$__v"
fi
if [ -n "$__wt" ]; then
  __out="$(__git_branch)"
  if [ -n "$__out" ]; then
    __sep; __emit '38;2;166;227;161' "$__out"
  fi
  __sep
  if [ "$(__git_dirty)" = '1' ]; then
    __emit '38;2;249;226;175' '✗'
  else
    __emit '38;2;249;226;175' '✓'
  fi
fi
__add="$(__field 'cost.total_lines_added')"
__del="$(__field 'cost.total_lines_removed')"
if [ -n "$__add" ] || [ -n "$__del" ]; then
  __sep
  __emit '92' "+$(__norm_int "$__add")"
  printf ' '
  __emit '91' "-$(__norm_int "$__del")"
fi
__reset

exit 0

EOF_STATUSLINE
chmod 755 "$dest/statusline.sh"

[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak"

if command -v jq >/dev/null 2>&1; then
  jq --arg cmd "$cmd" '.statusLine = {type:"command", command:$cmd}' "$settings.bak" > "$settings"
elif command -v node >/dev/null 2>&1; then
  SETTINGS="$settings" CMD="$cmd" node -e '
    const fs=require("fs"), p=process.env.SETTINGS;
    const s=JSON.parse(fs.readFileSync(p+".bak","utf8")||"{}");
    s.statusLine={type:"command",command:process.env.CMD};
    fs.writeFileSync(p, JSON.stringify(s,null,2)+"\n");'
else
  cp "$settings.bak" "$settings"
  echo "Neither jq nor node found. Add this to $settings manually:"
  echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$cmd\" }"
  exit 0
fi
echo "Installed. Settings backup: $settings.bak. Restart Claude Code to apply."

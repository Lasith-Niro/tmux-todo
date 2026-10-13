#!/usr/bin/env bash
# ==============================================================================
# todo.sh — Terminal Todo App with tmux side pane
# Part of tmux-todo plugin: https://github.com/LasithNiro/tmux-todo
#
# Usage:
#   todo --show            Open todo side pane
#   todo --hide            Close todo side pane
#   todo --toggle          Toggle todo side pane
#   todo add "task"        Add a new task
#   todo done <id>         Mark task as complete
#   todo remove <id>       Remove a task
#   todo list              Print list in current pane
#   todo clear             Remove all completed tasks
#   todo refresh-rate <s   Set refresh rate in seconds
#
# tmux.conf options:
#   set -g @todo-key             "t"      # toggle keybind (default: t)
#   set -g @todo-pane-width      "36"     # side pane width (default: 36)
#   set -g @todo-pane-side       "right"  # right or left (default: right)
#   set -g @todo-refresh-interval "120"   # refresh seconds (default: 120)
# ==============================================================================

DATA_DIR="${TODO_DATA_DIR:-$HOME/.local/share/todo}"
TODO_FILE="${TODO_FILE:-$DATA_DIR/todos.json}"
PANE_ID_FILE="$DATA_DIR/pane_id"
REFRESH_FILE="$DATA_DIR/refresh_interval"
export TODO_FILE

get_refresh_interval() {
  local interval
  if [ -f "$REFRESH_FILE" ]; then
    interval=$(cat "$REFRESH_FILE" 2>/dev/null)
  fi
  if [ -z "$interval" ]; then
    interval=$(tmux show-option -gv @todo-refresh-interval 2>/dev/null)
  fi
  echo "${interval:-120}"
}

# ── READ TPM OPTIONS (with defaults) ─────────────────────────────────────────
PANE_WIDTH=$(tmux show-option -gv @todo-pane-width 2>/dev/null)
PANE_WIDTH="${PANE_WIDTH:-36}"

PANE_SIDE=$(tmux show-option -gv @todo-pane-side 2>/dev/null)
PANE_SIDE="${PANE_SIDE:-right}"

REFRESH_INTERVAL=$(get_refresh_interval)

# ── COLORS ────────────────────────────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'

# ── SETUP ─────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$TODO_FILE")"

if [ ! -f "$TODO_FILE" ]; then
  echo '{"todos":[],"next_id":1}' > "$TODO_FILE"
fi

# ── RENDER ────────────────────────────────────────────────────────────────────
render_todos() {
  python3 << PYEOF
import json, os

TODO_FILE = os.environ.get("TODO_FILE", os.path.expanduser("~/.local/share/todo/todos.json"))
with open(TODO_FILE) as f:
    data = json.load(f)

todos   = data.get("todos", [])
pending = [t for t in todos if not t.get("done")]
done    = [t for t in todos if t.get("done")]

# Pane width from env (passed by watch loop)
pane_w  = int(os.environ.get("TODO_PANE_WIDTH", "36"))
line_w  = max(20, pane_w - 4)

R  = "\033[0m"
B  = "\033[1m"
D  = "\033[2m"
G  = "\033[0;32m"
Y  = "\033[1;33m"
Gr = "\033[0;90m"
C  = "\033[0;36m"
W  = "\033[1;37m"

border_top = f"{B}{C}  ── TODO " + "─" * max(0, line_w - 9) + f"{R}"
border_bot = f"{B}{C}  " + "─" * line_w + f"{R}"

def row(content, visible_len=0):
    print(f"  {content}")

def blank():
    print()

print()
print(border_top)
blank()

if not todos:
    msg = "No todos yet. Add one!"
    row(f"{Gr}{msg}{R}")
else:
    if pending:
        row(f"{B}{W}Pending{R}")
        for t in pending:
            tid     = str(t["id"]).rjust(2)
            max_len = max(10, line_w - 7)
            task    = t["task"][:max_len]
            row(f"{Y}[{tid}]{R} {task}")

    if done:
        blank()
        row(f"{B}{Gr}Completed{R}")
        for t in done:
            tid     = str(t["id"]).rjust(2)
            max_len = max(10, line_w - 7)
            task    = t["task"][:max_len]
            row(f"{G}[{tid}]{R} {D}{task}{R}")

blank()
summary = f"{len(done)}/{len(todos)} done"
row(f"{Gr}{summary}{R}")
print(border_bot)
print()
PYEOF
}

# ── WATCH LOOP (runs inside the side pane) ────────────────────────────────────
watch_loop() {
  export TODO_PANE_WIDTH="$PANE_WIDTH"
  local last_refresh=0
  local last_mtime=""
  local last_interval=""

  while true; do
    local current_interval
    current_interval=$(get_refresh_interval)

    local current_mtime=""
    if [ -f "$TODO_FILE" ]; then
      current_mtime=$(stat -f "%m" "$TODO_FILE" 2>/dev/null || stat -c "%Y" "$TODO_FILE" 2>/dev/null)
    fi

    local now
    now=$(date +%s)
    local elapsed=$((now - last_refresh))

    if [ "$current_mtime" != "$last_mtime" ] || [ "$current_interval" != "$last_interval" ] || [ "$elapsed" -ge "$current_interval" ]; then
      clear
      render_todos
      echo -e "  ${GRAY}↻ every ${current_interval}s  │  Prefix+$(tmux show-option -gv @todo-key 2>/dev/null || echo 't') to hide${RESET}"
      last_refresh=$now
      last_mtime="$current_mtime"
      last_interval="$current_interval"
    fi
    sleep 1
  done
}

# ── PANE HELPERS ──────────────────────────────────────────────────────────────
save_pane_id()  { echo "$1" > "$PANE_ID_FILE"; }
load_pane_id()  { [ -f "$PANE_ID_FILE" ] && cat "$PANE_ID_FILE" 2>/dev/null; }
clear_pane_id() { rm -f "$PANE_ID_FILE" 2>/dev/null; }

pane_alive() {
  local pid="$1"
  [ -n "$pid" ] && tmux list-panes -a -F "#{pane_id}" 2>/dev/null | grep -qx "$pid"
}

refresh_pane() {
  local pid
  pid=$(load_pane_id)
  if pane_alive "$pid"; then
    tmux send-keys -t "$pid" "" 2>/dev/null
  fi
  return 0
}

# ── COMMANDS ──────────────────────────────────────────────────────────────────
cmd_show() {
  if [ -z "$TMUX" ]; then
    echo -e "${RED}Error:${RESET} Not inside a tmux session. Run ${CYAN}tmux${RESET} first."
    exit 1
  fi

  local pid
  pid=$(load_pane_id)
  if pane_alive "$pid"; then
    echo -e "${YELLOW}ℹ${RESET}  Todo pane already open (pane $pid)."
    return
  fi

  # Determine split direction based on @todo-pane-side
  local split_flag="-h"
  [ "$PANE_SIDE" = "left" ] && split_flag="-hb"

  local new_pane
  new_pane=$(tmux split-window $split_flag -l "$PANE_WIDTH" -P -F "#{pane_id}" \
    "export TODO_PANE_WIDTH=$PANE_WIDTH; export TODO_REFRESH_INTERVAL=$REFRESH_INTERVAL; bash $0 --watch-loop")

  save_pane_id "$new_pane"
  echo -e "${GREEN}✓${RESET} Todo pane opened. (width: ${PANE_WIDTH}, side: ${PANE_SIDE})"
}

cmd_hide() {
  if [ -z "$TMUX" ]; then
    echo -e "${RED}Error:${RESET} Not inside a tmux session."
    exit 1
  fi

  local pid
  pid=$(load_pane_id)
  if pane_alive "$pid"; then
    tmux kill-pane -t "$pid"
    clear_pane_id
    echo -e "${GREEN}✓${RESET} Todo pane closed."
  else
    clear_pane_id
    echo -e "${YELLOW}ℹ${RESET}  No todo pane is open."
  fi
}

cmd_toggle() {
  local pid
  pid=$(load_pane_id)
  if pane_alive "$pid"; then
    cmd_hide
  else
    cmd_show
  fi
}

cmd_add() {
  local task="$1"
  if [ -z "$task" ]; then
    echo -e "${RED}Error:${RESET} Please provide a task."
    echo -e "  Usage: ${CYAN}todo add \"your task\"${RESET}"
    exit 1
  fi

  local escaped="${task//\'/\'\"\'\"\'}"
  python3 -c "
import json
with open('$TODO_FILE') as f:
    data = json.load(f)
new = {'id': data['next_id'], 'task': '$escaped', 'done': False}
data['todos'].append(new)
data['next_id'] += 1
with open('$TODO_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  local new_id
  new_id=$(python3 -c "import json; d=json.load(open('$TODO_FILE')); print(d['next_id']-1)")
  echo -e "${GREEN}✓${RESET} Added: ${WHITE}$task${RESET} ${GRAY}[#$new_id]${RESET}"
  refresh_pane
}

cmd_done() {
  local id="$1"
  if [ -z "$id" ]; then
    echo -e "${RED}Error:${RESET} Provide a task ID.  Usage: ${CYAN}todo done <id>${RESET}"
    exit 1
  fi

  local result
  result=$(python3 -c "
import json
with open('$TODO_FILE') as f:
    data = json.load(f)
found = False
for t in data['todos']:
    if t['id'] == $id:
        t['done'] = True
        found = True
        print(t['task'])
        break
if found:
    open('$TODO_FILE','w').write(json.dumps(data, indent=2))
else:
    print('NOT_FOUND')
")
  if [ "$result" = "NOT_FOUND" ]; then
    echo -e "${RED}Error:${RESET} Task #$id not found."
  else
    echo -e "${GREEN}✓${RESET} Completed: ${WHITE}$result${RESET}"
    refresh_pane
  fi
}

cmd_remove() {
  local id="$1"
  if [ -z "$id" ]; then
    echo -e "${RED}Error:${RESET} Provide a task ID.  Usage: ${CYAN}todo remove <id>${RESET}"
    exit 1
  fi

  local result
  result=$(python3 -c "
import json
with open('$TODO_FILE') as f:
    data = json.load(f)
name = next((t['task'] for t in data['todos'] if t['id'] == $id), 'NOT_FOUND')
if name != 'NOT_FOUND':
    data['todos'] = [t for t in data['todos'] if t['id'] != $id]
    open('$TODO_FILE','w').write(json.dumps(data, indent=2))
print(name)
")
  if [ "$result" = "NOT_FOUND" ]; then
    echo -e "${RED}Error:${RESET} Task #$id not found."
  else
    echo -e "${RED}✗${RESET} Removed: ${WHITE}$result${RESET}"
    refresh_pane
  fi
}

cmd_clear() {
  python3 -c "
import json
with open('$TODO_FILE') as f:
    data = json.load(f)
data['todos'] = [t for t in data['todos'] if not t.get('done')]
open('$TODO_FILE','w').write(json.dumps(data, indent=2))
"
  echo -e "${GREEN}✓${RESET} Cleared all completed tasks."
  refresh_pane
}

cmd_refresh_rate() {
  local rate="$1"
  if [ -z "$rate" ]; then
    local current
    current=$(get_refresh_interval)
    echo -e "Current refresh rate: ${CYAN}${current}s${RESET}"
    echo -e "Usage: ${CYAN}todo refresh-rate <seconds>${RESET}"
    return 0
  fi

  if ! [[ "$rate" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "${RED}Error:${RESET} Refresh rate must be a positive integer in seconds."
    echo -e "  Usage: ${CYAN}todo refresh-rate <seconds>${RESET}"
    exit 1
  fi

  mkdir -p "$(dirname "$REFRESH_FILE")"
  echo "$rate" > "$REFRESH_FILE"

  if [ -n "$TMUX" ] || tmux info &>/dev/null; then
    tmux set-option -g @todo-refresh-interval "$rate" 2>/dev/null
  fi

  echo -e "${GREEN}✓${RESET} Refresh rate set to ${WHITE}${rate}s${RESET}"
  refresh_pane
}

cmd_help() {
  local key
  key=$(tmux show-option -gv @todo-key 2>/dev/null || echo "t")
  echo -e "
${BOLD}${CYAN}  todo — tmux-todo${RESET}

  ${BOLD}Pane Control${RESET}
  ${CYAN}todo --show${RESET}              Open side pane
  ${CYAN}todo --hide${RESET}              Close side pane
  ${CYAN}todo --toggle${RESET}            Toggle side pane
  ${GRAY}Prefix + $key${RESET}             Toggle (keybind)

  ${BOLD}Tasks${RESET}
  ${CYAN}todo add \"task\"${RESET}          Add a new task
  ${CYAN}todo done <id>${RESET}           Mark as complete
  ${CYAN}todo remove <id>${RESET}         Remove a task
  ${CYAN}todo list${RESET}                Print list here
  ${CYAN}todo clear${RESET}               Remove completed

  ${BOLD}Configuration${RESET}
  ${CYAN}todo refresh-rate <sec>${RESET}  Set refresh rate in seconds (e.g. 120)

  ${BOLD}tmux.conf Options${RESET}
  ${GRAY}set -g @todo-key              \"t\"${RESET}
  ${GRAY}set -g @todo-pane-width       \"34\"${RESET}
  ${GRAY}set -g @todo-pane-side        \"right\"${RESET}
  ${GRAY}set -g @todo-refresh-interval \"2\"${RESET}
"
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
case "$1" in
  --show)                                                        cmd_show ;;
  --hide)                                                        cmd_hide ;;
  --toggle)                                                      cmd_toggle ;;
  --watch-loop)                                                  watch_loop ;;
  add)                                                           cmd_add "$2" ;;
  done)                                                          cmd_done "$2" ;;
  remove|rm)                                                     cmd_remove "$2" ;;
  clear)                                                         cmd_clear ;;
  refresh-rate|referesh-rate|refresh_rate|referesh_rate|refresh) cmd_refresh_rate "$2" ;;
  list|"")                                                       render_todos ;;
  --help|-h|help)                                                cmd_help ;;
  *)
    echo -e "${RED}Unknown command:${RESET} $1"
    cmd_help
    exit 1
    ;;
esac
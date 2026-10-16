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
#   todo refresh-rate <sec> Set refresh rate in seconds
#   todo scope <mode>      Set tab scope (current | all | follow)
#
# tmux.conf options:
#   set -g @todo-key              "t"        # toggle keybind (default: t)
#   set -g @todo-pane-width       "36"       # side pane width (default: 36)
#   set -g @todo-pane-side        "right"    # right or left (default: right)
#   set -g @todo-refresh-interval "120"      # refresh seconds (default: 120)
#   set -g @todo-scope            "current"  # current | all | follow (default: current)
# ==============================================================================

DATA_DIR="${TODO_DATA_DIR:-$HOME/.local/share/todo}"
TODO_FILE="${TODO_FILE:-$DATA_DIR/todos.json}"
PANE_ID_FILE="$DATA_DIR/pane_id"
REFRESH_FILE="$DATA_DIR/refresh_interval"
SCOPE_FILE="$DATA_DIR/scope"
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

get_scope() {
  local s
  if [ -f "$SCOPE_FILE" ]; then
    s=$(cat "$SCOPE_FILE" 2>/dev/null)
  fi
  if [ -z "$s" ]; then
    s=$(tmux show-option -gv @todo-scope 2>/dev/null)
  fi
  case "$s" in
    all|global)    echo "all" ;;
    follow|sticky) echo "follow" ;;
    *)             echo "current" ;;
  esac
}

get_split_flag() {
  if [ "$PANE_SIDE" = "left" ]; then
    echo "-hb"
  else
    echo "-h"
  fi
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
  [ -n "$pid" ] && pane_alive "$pid" && tmux send-keys -t "$pid" "" 2>/dev/null

  local follow_pid
  follow_pid=$(tmux show-option -gv @todo-follow-pane-id 2>/dev/null)
  [ -n "$follow_pid" ] && pane_alive "$follow_pid" && tmux send-keys -t "$follow_pid" "" 2>/dev/null

  if [ -n "$TMUX" ] || tmux info &>/dev/null; then
    for win in $(tmux list-windows -F "#{window_id}" 2>/dev/null); do
      local wpid
      wpid=$(tmux show-option -wv -t "$win" @todo-pane-id 2>/dev/null)
      if [ -n "$wpid" ] && pane_alive "$wpid"; then
        tmux send-keys -t "$wpid" "" 2>/dev/null
      fi
    done
  fi
  return 0
}

get_window_todo_pane() {
  local win="$1"
  [ -z "$win" ] && win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  [ -z "$win" ] && return 1

  local pid
  pid=$(tmux show-option -wv -t "$win" @todo-pane-id 2>/dev/null)
  if [ -n "$pid" ] && pane_alive "$pid"; then
    echo "$pid"
    return 0
  fi

  # Fallback: check if load_pane_id belongs to this window
  local fpid
  fpid=$(load_pane_id)
  if [ -n "$fpid" ] && pane_alive "$fpid"; then
    local fwin
    fwin=$(tmux display-message -p -t "$fpid" "#{window_id}" 2>/dev/null)
    if [ "$fwin" = "$win" ]; then
      echo "$fpid"
      return 0
    fi
  fi
  return 1
}

# ── CURRENT TAB SCOPE ─────────────────────────────────────────────────────────
cmd_show_current() {
  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local pid
  pid=$(get_window_todo_pane "$curr_win")
  if [ -n "$pid" ]; then
    echo -e "${YELLOW}ℹ${RESET}  Todo pane already open in this tab (pane $pid)."
    return 0
  fi

  local split_flag
  split_flag=$(get_split_flag)
  local new_pane
  new_pane=$(tmux split-window -d -t "$curr_win" $split_flag -l "$PANE_WIDTH" -P -F "#{pane_id}" \
    "export TODO_PANE_WIDTH=$PANE_WIDTH; export TODO_REFRESH_INTERVAL=$REFRESH_INTERVAL; bash $0 --watch-loop")

  tmux set-option -w -t "$curr_win" @todo-pane-id "$new_pane" 2>/dev/null
  save_pane_id "$new_pane"
  echo -e "${GREEN}✓${RESET} Todo pane opened in current tab. (width: ${PANE_WIDTH}, side: ${PANE_SIDE})"
}

cmd_hide_current() {
  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local pid
  pid=$(get_window_todo_pane "$curr_win")

  if [ -n "$pid" ] && pane_alive "$pid"; then
    tmux kill-pane -t "$pid" 2>/dev/null
    tmux set-option -u -w -t "$curr_win" @todo-pane-id 2>/dev/null
    clear_pane_id
    echo -e "${GREEN}✓${RESET} Todo pane closed in current tab."
  else
    tmux set-option -u -w -t "$curr_win" @todo-pane-id 2>/dev/null
    clear_pane_id
    echo -e "${YELLOW}ℹ${RESET}  No todo pane is open in this tab."
  fi
}

cmd_toggle_current() {
  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local pid
  pid=$(get_window_todo_pane "$curr_win")
  if [ -n "$pid" ]; then
    cmd_hide_current
  else
    cmd_show_current
  fi
}

# ── ALL TABS SCOPE ────────────────────────────────────────────────────────────
cmd_show_all() {
  local split_flag
  split_flag=$(get_split_flag)
  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local count=0

  tmux set-option -g @todo-all-state "on" 2>/dev/null

  for win in $(tmux list-windows -F "#{window_id}" 2>/dev/null); do
    local pid
    pid=$(get_window_todo_pane "$win")
    if [ -z "$pid" ]; then
      local new_pane
      new_pane=$(tmux split-window -d -t "$win" $split_flag -l "$PANE_WIDTH" -P -F "#{pane_id}" \
        "export TODO_PANE_WIDTH=$PANE_WIDTH; export TODO_REFRESH_INTERVAL=$REFRESH_INTERVAL; bash $0 --watch-loop")
      tmux set-option -w -t "$win" @todo-pane-id "$new_pane" 2>/dev/null
      [ "$win" = "$curr_win" ] && save_pane_id "$new_pane"
      count=$((count + 1))
    fi
  done
  echo -e "${GREEN}✓${RESET} Todo pane opened across all tabs ($count opened)."
}

cmd_hide_all() {
  tmux set-option -g @todo-all-state "off" 2>/dev/null
  local count=0
  for win in $(tmux list-windows -F "#{window_id}" 2>/dev/null); do
    local pid
    pid=$(tmux show-option -wv -t "$win" @todo-pane-id 2>/dev/null)
    if [ -n "$pid" ] && pane_alive "$pid"; then
      tmux kill-pane -t "$pid" 2>/dev/null
      count=$((count + 1))
    fi
    tmux set-option -u -w -t "$win" @todo-pane-id 2>/dev/null
  done
  local fpid
  fpid=$(load_pane_id)
  if [ -n "$fpid" ] && pane_alive "$fpid"; then
    tmux kill-pane -t "$fpid" 2>/dev/null
  fi
  clear_pane_id
  echo -e "${GREEN}✓${RESET} Todo pane closed across all tabs."
}

cmd_toggle_all() {
  local any_open=false
  for win in $(tmux list-windows -F "#{window_id}" 2>/dev/null); do
    local pid
    pid=$(get_window_todo_pane "$win")
    if [ -n "$pid" ]; then
      any_open=true
      break
    fi
  done

  if [ "$any_open" = true ]; then
    cmd_hide_all
  else
    cmd_show_all
  fi
}

cmd_hook_new_window() {
  local scope
  scope=$(get_scope)
  [ "$scope" != "all" ] && return 0

  local state
  state=$(tmux show-option -gv @todo-all-state 2>/dev/null)
  [ "$state" != "on" ] && return 0

  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local pid
  pid=$(get_window_todo_pane "$curr_win")
  if [ -z "$pid" ]; then
    local split_flag
    split_flag=$(get_split_flag)
    local new_pane
    new_pane=$(tmux split-window -d -t "$curr_win" $split_flag -l "$PANE_WIDTH" -P -F "#{pane_id}" \
      "export TODO_PANE_WIDTH=$PANE_WIDTH; export TODO_REFRESH_INTERVAL=$REFRESH_INTERVAL; bash $0 --watch-loop")
    tmux set-option -w -t "$curr_win" @todo-pane-id "$new_pane" 2>/dev/null
  fi
}

# ── FOLLOW SCOPE (Single pane moves with active tab) ──────────────────────────
cmd_show_follow() {
  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local follow_pid
  follow_pid=$(tmux show-option -gv @todo-follow-pane-id 2>/dev/null)
  [ -z "$follow_pid" ] && follow_pid=$(load_pane_id)
  local split_flag
  split_flag=$(get_split_flag)

  if [ -n "$follow_pid" ] && pane_alive "$follow_pid"; then
    local pane_win
    pane_win=$(tmux display-message -p -t "$follow_pid" "#{window_id}" 2>/dev/null)
    if [ "$pane_win" != "$curr_win" ]; then
      tmux join-pane -d -s "$follow_pid" -t "$curr_win" $split_flag -l "$PANE_WIDTH" 2>/dev/null
    fi
    echo -e "${YELLOW}ℹ${RESET}  Todo pane following current tab."
    return 0
  fi

  local new_pane
  new_pane=$(tmux split-window -d -t "$curr_win" $split_flag -l "$PANE_WIDTH" -P -F "#{pane_id}" \
    "export TODO_PANE_WIDTH=$PANE_WIDTH; export TODO_REFRESH_INTERVAL=$REFRESH_INTERVAL; bash $0 --watch-loop")

  tmux set-option -g @todo-follow-pane-id "$new_pane" 2>/dev/null
  save_pane_id "$new_pane"
  echo -e "${GREEN}✓${RESET} Todo pane opened (following active tab)."
}

cmd_hide_follow() {
  local follow_pid
  follow_pid=$(tmux show-option -gv @todo-follow-pane-id 2>/dev/null)
  [ -z "$follow_pid" ] && follow_pid=$(load_pane_id)

  if [ -n "$follow_pid" ] && pane_alive "$follow_pid"; then
    tmux kill-pane -t "$follow_pid" 2>/dev/null
    tmux set-option -u -g @todo-follow-pane-id 2>/dev/null
    clear_pane_id
    echo -e "${GREEN}✓${RESET} Todo pane closed."
  else
    tmux set-option -u -g @todo-follow-pane-id 2>/dev/null
    clear_pane_id
    echo -e "${YELLOW}ℹ${RESET}  No todo pane is open."
  fi
}

cmd_toggle_follow() {
  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local follow_pid
  follow_pid=$(tmux show-option -gv @todo-follow-pane-id 2>/dev/null)
  [ -z "$follow_pid" ] && follow_pid=$(load_pane_id)
  local split_flag
  split_flag=$(get_split_flag)

  if [ -n "$follow_pid" ] && pane_alive "$follow_pid"; then
    local pane_win
    pane_win=$(tmux display-message -p -t "$follow_pid" "#{window_id}" 2>/dev/null)
    if [ "$pane_win" = "$curr_win" ]; then
      cmd_hide_follow
    else
      tmux join-pane -d -s "$follow_pid" -t "$curr_win" $split_flag -l "$PANE_WIDTH" 2>/dev/null
      echo -e "${GREEN}✓${RESET} Todo pane moved to current tab."
    fi
  else
    cmd_show_follow
  fi
}

cmd_hook_select_window() {
  local scope
  scope=$(get_scope)
  [ "$scope" != "follow" ] && return 0

  local follow_pid
  follow_pid=$(tmux show-option -gv @todo-follow-pane-id 2>/dev/null)
  [ -z "$follow_pid" ] && follow_pid=$(load_pane_id)
  [ -z "$follow_pid" ] && return 0
  ! pane_alive "$follow_pid" && return 0

  local curr_win
  curr_win=$(tmux display-message -p "#{window_id}" 2>/dev/null)
  local pane_win
  pane_win=$(tmux display-message -p -t "$follow_pid" "#{window_id}" 2>/dev/null)

  if [ -n "$curr_win" ] && [ -n "$pane_win" ] && [ "$curr_win" != "$pane_win" ]; then
    local split_flag
    split_flag=$(get_split_flag)
    tmux join-pane -d -s "$follow_pid" -t "$curr_win" $split_flag -l "$PANE_WIDTH" 2>/dev/null
  fi
}

# ── COMMANDS DISPATCHER ───────────────────────────────────────────────────────
cmd_show() {
  if [ -z "$TMUX" ]; then
    echo -e "${RED}Error:${RESET} Not inside a tmux session. Run ${CYAN}tmux${RESET} first."
    exit 1
  fi
  local scope
  scope=$(get_scope)
  case "$scope" in
    all)    cmd_show_all ;;
    follow) cmd_show_follow ;;
    *)      cmd_show_current ;;
  esac
}

cmd_hide() {
  if [ -z "$TMUX" ]; then
    echo -e "${RED}Error:${RESET} Not inside a tmux session."
    exit 1
  fi
  local scope
  scope=$(get_scope)
  case "$scope" in
    all)    cmd_hide_all ;;
    follow) cmd_hide_follow ;;
    *)      cmd_hide_current ;;
  esac
}

cmd_toggle() {
  if [ -z "$TMUX" ]; then
    echo -e "${RED}Error:${RESET} Not inside a tmux session."
    exit 1
  fi
  local scope
  scope=$(get_scope)
  case "$scope" in
    all)    cmd_toggle_all ;;
    follow) cmd_toggle_follow ;;
    *)      cmd_toggle_current ;;
  esac
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

cmd_scope() {
  local target="$1"
  if [ -z "$target" ]; then
    local current
    current=$(get_scope)
    echo -e "Current todo scope: ${CYAN}${current}${RESET}"
    echo -e ""
    echo -e "Available options:"
    echo -e "  ${WHITE}current${RESET}  Open/close only in active tab (default)"
    echo -e "  ${WHITE}all${RESET}      Open/close across all tabs simultaneously"
    echo -e "  ${WHITE}follow${RESET}   Single pane automatically follows active tab"
    echo -e ""
    echo -e "Usage: ${CYAN}todo scope <current|all|follow>${RESET}"
    return 0
  fi

  case "$target" in
    current|window|single) target="current" ;;
    all|global)            target="all" ;;
    follow|sticky)         target="follow" ;;
    *)
      echo -e "${RED}Error:${RESET} Invalid scope '$target'."
      echo -e "  Available options: ${CYAN}current${RESET}, ${CYAN}all${RESET}, ${CYAN}follow${RESET}"
      echo -e "  Usage: ${CYAN}todo scope <current|all|follow>${RESET}"
      exit 1
      ;;
  esac

  mkdir -p "$(dirname "$SCOPE_FILE")" 2>/dev/null
  echo "$target" > "$SCOPE_FILE"

  if [ -n "$TMUX" ] || tmux info &>/dev/null; then
    tmux set-option -g @todo-scope "$target" 2>/dev/null
  fi

  echo -e "${GREEN}✓${RESET} Todo scope set to ${WHITE}${target}${RESET}"
}

cmd_help() {
  local key
  key=$(tmux show-option -gv @todo-key 2>/dev/null || echo "t")
  local current_scope
  current_scope=$(get_scope)
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
  ${CYAN}todo scope <mode>${RESET}        Set tab scope: current | all | follow (current: ${current_scope})

  ${BOLD}tmux.conf Options${RESET}
  ${GRAY}set -g @todo-key              \"t\"${RESET}
  ${GRAY}set -g @todo-pane-width       \"34\"${RESET}
  ${GRAY}set -g @todo-pane-side        \"right\"${RESET}
  ${GRAY}set -g @todo-refresh-interval \"2\"${RESET}
  ${GRAY}set -g @todo-scope            \"current\"${RESET}  # current | all | follow
"
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
case "$1" in
  --show)                                                        cmd_show ;;
  --hide)                                                        cmd_hide ;;
  --toggle)                                                      cmd_toggle ;;
  --watch-loop)                                                  watch_loop ;;
  --hook-new-window)                                             cmd_hook_new_window ;;
  --hook-select-window)                                          cmd_hook_select_window ;;
  add)                                                           cmd_add "$2" ;;
  done)                                                          cmd_done "$2" ;;
  remove|rm)                                                     cmd_remove "$2" ;;
  clear)                                                         cmd_clear ;;
  refresh-rate|referesh-rate|refresh_rate|referesh_rate|refresh) cmd_refresh_rate "$2" ;;
  scope|--scope)                                                 cmd_scope "$2" ;;
  list|"")                                                       render_todos ;;
  --help|-h|help)                                                cmd_help ;;
  *)
    echo -e "${RED}Unknown command:${RESET} $1"
    cmd_help
    exit 1
    ;;
esac
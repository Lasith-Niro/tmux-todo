#!/usr/bin/env bash
# ==============================================================================
# todo.tmux — tmux-todo plugin entry point
# ==============================================================================

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make todo.sh executable
chmod +x "$CURRENT_DIR/scripts/todo.sh"

# Create a symlink in ~/.local/bin so 'todo' works from anywhere
mkdir -p "$HOME/.local/bin"
ln -sf "$CURRENT_DIR/scripts/todo.sh" "$HOME/.local/bin/todo"

# Bind key (default prefix + t): show/hide todo pane
TODO_KEY=$(tmux show-option -gv @todo-key 2>/dev/null)
TODO_KEY="${TODO_KEY:-t}"
tmux bind-key "$TODO_KEY" run-shell "$CURRENT_DIR/scripts/todo.sh --toggle"

# Hooks for 'all' (auto-open on new tab) and 'follow' (follow active tab)
tmux set-hook -g after-new-window "run-shell '$CURRENT_DIR/scripts/todo.sh --hook-new-window'"
tmux set-hook -g after-select-window "run-shell '$CURRENT_DIR/scripts/todo.sh --hook-select-window'"
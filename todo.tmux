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
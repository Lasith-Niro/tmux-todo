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

# Bind default key: prefix + t = show/hide todo pane
tmux bind-key t run-shell "$CURRENT_DIR/scripts/todo.sh --toggle"
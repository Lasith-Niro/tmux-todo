# tmux-todo

A lightweight terminal todo app with a live tmux side pane. No dependencies beyond `python3` and `bash`.

## Features

- Live-updating side pane inside tmux
- Toggle pane with a single keybind
- Add, complete, remove tasks from any pane
- Configurable width, side, refresh rate, and keybind
- Stores todos in `~/.local/share/todo/todos.json`

## Installation

### Via TPM (recommended)

Add to `~/.tmux.conf`:
```
set -g @plugin 'Lasith-Niro/tmux-todo'
```
Then press `Prefix + I` to install.

### Manual

```bash
git clone https://github.com/Lasith-Niro/tmux-todo ~/.tmux/plugins/tmux-todo
~/.tmux/plugins/tmux-todo/todo.tmux
```

## Usage

| Command | Description |
|---|---|
| `todo --show` | Open side pane |
| `todo --hide` | Close side pane |
| `todo --toggle` | Toggle side pane |
| `todo add "task"` | Add a task |
| `todo done <id>` | Mark as complete |
| `todo remove <id>` | Remove a task |
| `todo list` | Print list in current pane |
| `todo clear` | Remove all completed tasks |
| `todo refresh-rate <sec>` | Set refresh rate in seconds (e.g. `todo refresh-rate 120`) |
| `todo scope <mode>` | Set tab scope: `current`, `all`, or `follow` |
| `Prefix + t` | Toggle pane (keybind) |

## Configuration

Add any of these to `~/.tmux.conf` before the plugin line:

```tmux
set -g @todo-key              "t"        # toggle keybind     (default: t)
set -g @todo-pane-width       "34"       # side pane width    (default: 34)
set -g @todo-pane-side        "right"    # right or left      (default: right)
set -g @todo-refresh-interval "2"        # refresh in seconds (default: 2)
set -g @todo-scope            "current"  # current, all, or follow (default: current)
```

### Tab Scopes

- **`current`** *(default)*: Toggling opens or closes the todo pane only in the active tab. Other tabs are unaffected.
- **`all`**: Toggling opens or closes the todo pane across all tabs simultaneously. New tabs automatically get the pane while active.
- **`follow`**: A single todo pane automatically follows you to whichever tab you switch to.

## Example `~/.tmux.conf`

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'LasithNiro/tmux-todo'

set -g @todo-key              "t"
set -g @todo-pane-width       "40"
set -g @todo-pane-side        "right"
set -g @todo-refresh-interval "2"
set -g @todo-scope            "current"

run '~/.tmux/plugins/tpm/tpm'
```

## Requirements

- tmux >= 2.4
- bash >= 3.2 (macOS default is fine)
- python3

## License

MIT

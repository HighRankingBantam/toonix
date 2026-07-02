# Tmux Keybindings Reference

**Prefix:** `Ctrl+Space` (fallback: `Ctrl+b`)

`P` below means "press the prefix, release, then press the next key." Bindings without `P` work directly (no prefix needed).

When tmux is waiting for the second key after a prefix press, the status bar shows `PREFIX` on the right.

---

## Panes

| Key | Action |
|---|---|
| `Alt+Enter` | Split stacked (new pane below) |
| `Alt+Shift+Enter` | Split side-by-side (new pane right) |
| `Alt+Escape` | Kill pane |
| `P h` | Split stacked |
| `P v` | Split side-by-side |
| `P x` | Kill pane |
| `Ctrl+Alt+←/↓/↑/→` | Move focus between panes |
| `Ctrl+Alt+Shift+←/↓/↑/→` | Resize pane by 5 |
| `P z` | Toggle pane zoom (fullscreen current pane) |
| `P Space` | Cycle pane layouts |

## Windows

| Key | Action |
|---|---|
| `P c` | New window (in current path) |
| `P k` | Kill window |
| `P r` | Rename window |
| `Alt+1` .. `Alt+9` | Jump to window 1–9 |
| `Alt+←` / `Alt+→` | Previous / next window |
| `Alt+Shift+←` / `Alt+Shift+→` | Move window left / right |

## Sessions

| Key | Action |
|---|---|
| `P C` | New session (in current path) |
| `P K` | Kill session |
| `P R` | Rename session |
| `P P` / `P N` | Previous / next session |
| `Alt+↑` / `Alt+↓` | Previous / next session |
| `P d` | Detach from session |

## Copy Mode (vi-style)

| Key | Action |
|---|---|
| `P [` | Enter copy mode |
| `v` | Begin selection (inside copy mode) |
| `y` | Copy selection and exit (inside copy mode) |
| `q` or `Escape` | Exit copy mode |

## Misc

| Key | Action |
|---|---|
| `P ?` | Popup with all keybindings |
| `P q` | Reload config |
| Mouse | Click panes/windows, drag borders, scroll history |

---

## CLI: Sessions (run from any shell)

| Command | Action |
|---|---|
| `tmux` | Start new session (auto-named) |
| `tmux new -s NAME` | Start new named session |
| `tmux new -s NAME -d` | Create session detached (don't attach yet) |
| `tmux ls` | List sessions |
| `tmux a` / `tmux attach` | Attach to last session |
| `tmux a -t NAME` | Attach to specific session |
| `tmux a -d -t NAME` | Attach and detach any other clients (steal it) |
| `tmux rename-session -t OLD NEW` | Rename a session |
| `tmux kill-session -t NAME` | Kill one session |
| `tmux kill-server` | Kill everything (all sessions, all clients) |
| `tmux switch -t NAME` | Switch attached client to another session |

## CLI: Send commands into a running session

| Command | Action |
|---|---|
| `tmux send-keys -t NAME "cmd" Enter` | Run a command in session's active pane |
| `tmux send-keys -t NAME:WIN.PANE "cmd" Enter` | Target specific window/pane |
| `tmux capture-pane -t NAME -p` | Print contents of a pane to stdout |
| `tmux display-message -p '#S'` | Print current session name |

## Inside tmux: Command prompt

Press `Ctrl+Space` then `:` to open the command prompt. Useful one-liners:

| Command | Action |
|---|---|
| `:new-window` | New window (same as `P c`) |
| `:kill-pane -a` | Kill all panes except the current one |
| `:join-pane -s NAME:WIN` | Pull a pane from another window into this one |
| `:break-pane` | Split current pane out into its own window |
| `:resize-pane -x 80 -y 24` | Resize current pane to exact size |
| `:select-layout tiled` | Re-tile all panes evenly |
| `:select-layout main-vertical` | One big pane left, stacked panes right |
| `:setw synchronize-panes on` | Type to ALL panes at once (off to disable) |
| `:clock-mode` | Show big clock in pane (any key exits) |
| `:show-options -g` | Dump all global options |
| `:list-keys` | Dump every binding |
| `:source ~/.config/tmux/tmux.conf` | Reload config (same as `P q`) |

## Useful patterns

```sh
# Reattach if a session exists, create it if not
tmux new -A -s work

# Start a dev session with two windows pre-built, then attach
tmux new -d -s dev -c ~/Projects/SonicHysteria
tmux send-keys -t dev "vim" Enter
tmux new-window -t dev -c ~/Projects/SonicHysteria
tmux send-keys -t dev "make run" Enter
tmux a -t dev

# Kill everything except the session you're in
tmux ls -F '#S' | grep -v "^$(tmux display -p '#S')$" | xargs -I{} tmux kill-session -t {}
```

## Pane / window addressing

When commands take a `-t` target, format is `session:window.pane`:

- `work` — session "work"
- `work:2` — window 2 in "work"
- `work:2.1` — pane 1 of window 2 in "work"
- `work:editor` — window named "editor"
- `.1` — pane 1 of current window
- `!` — the previously-active pane

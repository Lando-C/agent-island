# Terminal Jump Matrix

Agent Island records the route used for the latest terminal jump in **Settings
> Diagnostics > Terminal Focus Matrix**. `Exact` means the terminal exposes a
stable session/pane identity that Agent Island can select. `Context` uses exact
TTY or working-directory matching. `Fallback` only raises the correct terminal
application and is intentionally reported as such.

| Terminal | Primary route | Fallback | Reported route |
| --- | --- | --- | --- |
| tmux | socket + client + pane ID | backing terminal | `tmux exact pane` / `tmux fallback terminal` |
| iTerm2 | AppleScript session ID, window/tab, then TTY | app activation | `iTerm2 session/TTY` |
| Terminal.app | AppleScript TTY | app activation | `Terminal TTY` |
| Ghostty | Accessibility/TTY and CWD matching | app activation | `Ghostty accessibility/TTY` |
| WezTerm | `wezterm cli activate-pane` across GUI sockets | TTY/CWD pane lookup, app activation | `WezTerm exact pane` / `WezTerm TTY/CWD pane` |
| kitty | remote-control window ID | CWD matching, app activation | `kitty exact window` / `kitty CWD match` |
| cmux | tab/terminal IDs via its local command interface | app activation | `cmux tab/terminal` |
| Warp, Kaku, Wave, Alacritty | app activation where no verified pane API is available | process activation | `application activation fallback` |

The matrix is conservative. Missing tmux, WezTerm, or kitty helper facilities
are optional capability warnings, not application failures. A failed exact
route never causes Agent Island to claim it selected a pane it could not verify.

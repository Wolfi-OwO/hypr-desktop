# Keybindings

`SUPER` is the modifier. Bindings mirror the GNOME defaults this configuration
replaces, so muscle memory carries over.

## Launching

| Key | Action |
|---|---|
| `CTRL+ALT+S` | Applications menu (the Quickshell one, with search) |
| `SUPER+A` | Same |
| `SUPER+R` | Same |
| `ALT+F2` | Run dialog (rofi — takes an arbitrary command) |
| `SUPER+Return` / `SUPER+Q` | Terminal |
| `SUPER+E` | File manager |
| `SUPER+B` | Browser |
| `SUPER+L` | Lock |
| `CTRL+ALT+Delete` | Logout menu |

## Windows

| Key | Action |
|---|---|
| `ALT+Tab` | Switcher overlay; hold Alt, release to commit |
| `ALT+SHIFT+Tab` | Backwards |
| `Down arrow` (overlay open) | Expand an application's windows |
| `Escape` (overlay open) | Cancel |
| `SUPER+Tab` | Plain cycling, no overlay |
| `ALT+F4` | Close |
| `SUPER+V` | Toggle floating |
| `SUPER+arrows` | Focus by direction |

Note: while the overlay holds exclusive keyboard focus, Hyprland binds stop
firing entirely. All overlay navigation therefore lives in `AltTab.qml`, not in
the Hyprland config.

## Workspaces

| Key | Action |
|---|---|
| `CTRL+ALT+Left/Right` | Previous / next workspace |
| `SUPER+1..0` | Go to workspace |
| `SUPER+SHIFT+1..0` | Move window to workspace |

## Shell

| Key | Action |
|---|---|
| `SUPER+N` | Pop the last notification |
| `Print` | Region screenshot |
| Media keys | Volume, brightness, playback |

## Neovim

Leader is `Space`.

### Debugging

| Key | Action |
|---|---|
| `F5` | Start / continue |
| `F9` | Toggle breakpoint |
| `F10` / `F11` / `F12` | Step over / into / out |
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint |
| `<leader>du` | Toggle debugger UI |
| `<leader>de` | Evaluate expression (also visual) |
| `<leader>dm` | Debug the test under the cursor (Python) |

### LSP

| Key | Action |
|---|---|
| `gd` / `gr` / `gI` / `gy` | Definition / references / implementation / type |
| `K` | Hover |
| `<leader>rn` | Rename |
| `<leader>ca` | Code action |
| `[d` / `]d` | Previous / next diagnostic |
| `<leader>th` | Toggle inlay hints |

### Java

| Key | Action |
|---|---|
| `<leader>jo` | Organise imports |
| `<leader>jv` / `<leader>jc` / `<leader>jm` | Extract variable / constant / method |
| `<leader>jt` / `<leader>jT` | Test method / class |

### Editing

| Key | Action |
|---|---|
| `<C-f>i` | Format buffer or selection |
| `<leader>tf` | Toggle format on save |
| `]h` / `[h` | Next / previous git hunk |
| `<leader>gs` / `<leader>gr` | Stage / reset hunk |
| `<leader>gb` | Blame line |
| `gcc` / `gc` | Comment line / motion |

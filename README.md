# SSH Dock

SSH launcher dock for the [Omarchy](https://omarchy.org) bar. Connect to your servers with a click, see which sessions are live, and get a light when a server pings you.

![preview](preview.png)

## Features

- Server list auto-imported from `~/.ssh/config` (wildcard/negated patterns skipped)
- Live session detection via ControlMaster sockets and running `ssh` processes
- Connection modes: `plain` ssh, `tmux` attach-or-create, `herdr --remote`, or your own command template
- Per-server overrides and alert lights driven by desktop notifications

## Install

```bash
omarchy plugin add https://github.com/moneytosms/omarchy-ssh-dock.git
```

Then enable **SSH Dock** from the plugin drawer (or `omarchy plugin enable io.github.moneytosms.ssh-dock right`).

## Keybindings

### Standalone fuzzy picker (no panel)

`omarchy-ssh-dock-pick` lists your `~/.ssh/config` hosts in Omarchy's native
menu and connects on selection — skips opening the bar panel entirely. Bind
it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("ALT + S", "SSH Dock picker", "~/.config/omarchy/plugins/io.github.moneytosms.ssh-dock/omarchy-ssh-dock-pick")
```

It only lists servers present in `~/.ssh/config` — manual/panel-only entries
still need the bar panel.

### Via the widget's IPC target

The widget also registers an IPC target, so you can bind panel toggling or
per-server connects directly:

```lua
o.bind("SUPER + S", "SSH Dock", "omarchy-shell io.github.moneytosms.ssh-dock pick")
o.bind("SUPER + F1", "SSH web01", "omarchy-shell io.github.moneytosms.ssh-dock connect web01")
```

`pick` opens the panel with the filter focused; `connect <alias>` launches the server directly. Other IPC functions: `toggle`, `echo <alias>` (print the command without running it), `status`, `clear all`, `refresh`, `ping`.

In `herdr` mode servers are launched via `herdr --remote user@host`. Servers can light up their dock entry by emitting desktop notifications that mention their alias or a keyword — e.g. `herdr notification show "web01 cpu high"` locally, or over ssh: `ssh web01 notify-send "deploy" "web01 done"`.

## Roadmap

- [x] Connect engine (plain / tmux / herdr / custom template) — click to ssh
- [x] Alert lights: widget changes color when a notification mentions a server
- [x] Manual servers + per-host overrides (terminal, mode, color/glyph, keywords)
- [x] Fuzzy picker + `connect <alias>` IPC for keybinds

## License

MIT

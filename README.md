# SSH Dock

SSH launcher dock for the [Omarchy](https://omarchy.org) bar. Connect to your servers with a click, see which sessions are live, and get a light when a server pings you.

![preview](preview.png)

## Features

- Server list auto-imported from `~/.ssh/config` (wildcard/negated patterns skipped)
- Live session detection via ControlMaster sockets and running `ssh` processes
- Connection modes: `plain` ssh, `tmux` attach-or-create, `herdr --remote`, or your own command template
- Per-server overrides and alert lights driven by desktop notifications (planned)

## Install

```bash
omarchy plugin add https://github.com/moneytosms/omarchy-ssh-dock.git
```

Then enable **SSH Dock** from the plugin drawer (or `omarchy plugin enable io.github.moneytosms.ssh-dock right`).

## Keybindings

The widget registers an IPC target, so you can bind panel toggling:

```
bind = SUPER, S, exec, omarchy-shell io.github.moneytosms.ssh-dock toggle
```

Per-server connect shortcuts and a server picker are on the roadmap.

## Roadmap

- [ ] Connect engine (plain / tmux / herdr / custom template) — click to ssh
- [ ] Alert lights: widget changes color when a notification mentions a server
- [ ] Manual servers + per-host overrides (terminal, mode, color/glyph, keywords)
- [ ] Fuzzy picker + `connect <alias>` IPC for keybinds

## License

MIT

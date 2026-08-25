# SSH Dock

SSH launcher dock for the [Omarchy](https://omarchy.org) bar. Connect to your servers with a click, see which sessions are live, and get a light when a server pings you.

![preview](preview.png)

## Features

- Server list auto-imported from `~/.ssh/config` (wildcard/negated patterns skipped)
- Live session detection via ControlMaster sockets and running `ssh` processes
- Connection modes: `plain` ssh, `tmux` attach-or-create, `herdr --remote`, or your own command template
- Per-server overrides (display name, host/user/port, terminal, mode, color/glyph, keywords, hidden) and alert lights driven by desktop notifications
- Standalone fuzzy picker command, independent of the bar panel

## Requirements

- `jq` (server list parsing, both the widget's helper and the standalone picker)
- `herdr` — only if you use `herdr` connect mode
- Omarchy's stock terminal launcher (`omarchy-launch-terminal`) or your own `terminalCommand` override

## Install

```bash
omarchy plugin add https://github.com/moneytosms/omarchy-ssh-dock.git
```

Then enable **SSH Dock** from the plugin drawer (or `omarchy plugin enable io.github.moneytosms.ssh-dock right`).

## Adding servers

SSH Dock reads `Host` entries straight out of `~/.ssh/config` — no manual
step required beyond having your servers there already. A minimal entry:

```
Host myserver
    HostName myserver.example.com
    User myuser
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

For [Tailscale](https://tailscale.com) boxes, use the MagicDNS name or the
`100.x.y.z` tailnet IP as `HostName` — find both with `tailscale status`:

```
Host web01
    HostName web01.your-tailnet.ts.net
    User youruser
```

Wildcard hosts (`Host *`) and negated patterns are skipped automatically —
they're config templates, not servers.

Once a `Host` block exists, run `omarchy-shell io.github.moneytosms.ssh-dock status`
to confirm SSH Dock picked it up (`servers` count goes up), or just open the
picker — it appears immediately, no restart needed.

## Naming servers

By default the dock shows the SSH alias. To give a server a friendlier
display name (shown in both the bar panel and the standalone picker):

1. Open the bar panel, hover the server row, click the pencil icon (or
   right-click the row) to expand its editor.
2. Fill in **display name**, hit **Save**.

If no name is set, the label falls back to host, then user, then the raw
alias — so it's never blank. Setting a name doesn't change what you type to
connect (`connect <alias>` still uses the SSH alias); it only changes the
label shown.

## Keybindings

### Standalone fuzzy picker (no panel)

`omarchy-ssh-dock-pick` lists your servers in Omarchy's native menu —
showing display name/host overrides from the panel — and connects on
selection. It never opens the bar panel. Bind it in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("ALT + S", "SSH Dock picker", "~/.config/omarchy/plugins/io.github.moneytosms.ssh-dock/omarchy-ssh-dock-pick")
```

It lists servers present in `~/.ssh/config`, with panel overrides (name,
host/user/port, hidden) merged in — manual/panel-only entries (added purely
via the "Add server" form, not present in `~/.ssh/config`) still need the
bar panel.

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
- [x] Manual servers + per-host overrides (terminal, mode, color/glyph, keywords, display name)
- [x] Fuzzy picker + `connect <alias>` IPC for keybinds
- [x] Standalone picker command, independent of the bar panel

## License

MIT

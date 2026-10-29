# Oshelly

Run your shell commands from the Omarchy bar, in your terminal.

Click the terminal icon, click a name, and the command opens in the default
terminal. The list is a small text file you already know how to edit:

```sh
# ~/.config/oshelly/oshelly.conf

Restart audio: systemctl --user restart pipewire wireplumber
Update system: omarchy update
Tail the journal: journalctl -f
```

The panel is only a front end. It runs [oshelly-cli][cli], which owns the
config format and the terminal launch, so the same file drives the
[macOS menu bar app][mac] and neither front end can disagree with the other
about what a name means.

## Dependencies

| | What | Why | Required |
|---|---|---|---|
| Panel | [`oshelly`](https://github.com/h1st0ry3D/oshelly-cli) | Reads the config and opens the terminal | **Yes** |
| Build | Go 1.22 or newer | Building the CLI | To build only |

A terminal is required, which every desktop has. If the CLI cannot find one it
says so instead of pretending the command ran.

## Install

### 1. The CLI

```bash
git clone https://github.com/h1st0ry3D/oshelly-cli
cd oshelly-cli
go build -trimpath -o ~/.local/bin/oshelly ./cmd/oshelly
```

`/usr/local/bin` works too. The panel looks in `/usr/local/bin` first and
`~/.local/bin` second, so either is found with no configuration.

### 2. The config

```bash
mkdir -p ~/.config/oshelly
$EDITOR ~/.config/oshelly/oshelly.conf
```

One command per line, `name: command`. A line starting with `#` is a comment.
A name can contain spaces; a name cannot contain a colon. Everything after the
first colon is the command and is passed to the terminal unchanged.

```sh
Restart audio: systemctl --user restart pipewire wireplumber
Screenshot: grim -g "$(slurp)" - | wl-copy
Update: omarchy update
```

### 3. The plugin

It is not in the Omarchy marketplace yet. Clone it and link it in:

```bash
git clone https://github.com/h1st0ry3D/oshelly "$HOME/github/oshelly"

# Relative target, so the link survives a different username or home directory.
ln -sfn ../../../github/oshelly "$HOME/.config/omarchy/plugins/h1st0ry3d.oshelly"

omarchy plugin enable h1st0ry3d.oshelly --section right
omarchy restart shell
```

Adjust the number of `../` segments if you clone somewhere else, or replace the
link with an absolute path if you prefer.

Rename the symlink and the `id` in `manifest.json`, `moduleName` and
`ipcTarget` if you fork it under your own name.

### 4. Check it

In a terminal:

```bash
oshelly doctor
oshelly list
```

`doctor` prints the config path, the number of commands and which terminal and
editor were chosen. Then open the panel and click one.

### Updating

```bash
# 1. The CLI
cd ~/github/oshelly-cli
git pull
go build -trimpath -o ~/.local/bin/oshelly ./cmd/oshelly

# 2. The plugin
cd ~/github/oshelly
git pull

# 3. The shell, to pick the plugin up
omarchy restart shell
```

The panel reads the config every time it opens, so a change to the text file
needs no restart. Only a change to `Panel.qml` does.

### Uninstall

Disable it, then delete the plugin link and restart:

```bash
omarchy plugin disable h1st0ry3d.oshelly
rm ~/.config/omarchy/plugins/h1st0ry3d.oshelly
omarchy restart shell
```

Your commands live in `~/.config/oshelly/oshelly.conf`, not in the plugin, so
they survive. Delete that file too if you want them gone.

## Use

Click the bar icon, then click a command. The panel closes and the command
starts in a terminal.

The arrow keys move the highlighted row and Enter launches it. Escape closes
the panel. The panel opens on a clean status line and picks up an edit to the
config the next time it is opened.

The **Edit** button in the header opens the config in your default editor. On
Omarchy that is `omarchy-launch-config-editor`, which opens a terminal for a
TUI editor and a window for a GUI one. The panel closes once the editor has
been started; if the config does not exist yet, the CLI creates it with a
commented header first.

The terminal stays open when the command finishes, showing its exit status and
an interactive shell. A failed script has to stay on screen long enough to read
the error, so the terminal does not close on its own. Close the window when you
are done reading.

Each row has a power button on the right. With it selected, the wrapper exits
after the command instead of opening a shell, so the terminal closes the
session. With it unselected, the terminal stays open. The choice is stored in
`settings.json` and applies to the next run. A terminal profile configured to
always keep the window open can still keep it after the shell exits.

### Which terminal

The CLI uses, in order:

1. `OSHELLY_TERMINAL`, if set.
2. The choice saved with `oshelly terminal`.
3. `omarchy-launch-terminal`, which is Omarchy's own launcher and starts the
   terminal through `uwsm`.
4. `xdg-terminal-exec`.
5. `$TERMINAL`.
6. The first of ghostty, alacritty, kitty, foot, wezterm, konsole,
   gnome-terminal, xfce4-terminal and xterm that is installed.

The panel has no terminal picker of its own. To force one for this machine:

```sh
oshelly terminal ghostty
oshelly terminal default
```

`oshelly doctor` prints which one it found. To force one for the panel, export
`OSHELLY_TERMINAL` in the environment the shell starts in:

```sh
OSHELLY_TERMINAL=ghostty
```

A value that cannot be found is an error rather than a silent fallback, because
the setting exists to choose the terminal.

### Which editor

The Edit button asks the CLI, which uses:

1. `OSHELLY_EDITOR`, if set.
2. `omarchy-launch-config-editor`, which reads Omarchy's default editor and
   opens a terminal for a TUI editor or a window for a GUI one.
3. `omarchy-launch-editor`.
4. `xdg-open`.

`oshelly doctor` prints the editor it found. Change Omarchy's default with
`omarchy default editor <name>`; set `OSHELLY_EDITOR` in the environment the
shell starts in to choose one for this tool only. For a TUI editor, set it to
`omarchy-launch-editor`, which opens a terminal.

## Troubleshooting

### The panel says oshelly is not installed

It looked in `/usr/local/bin/oshelly` and `~/.local/bin/oshelly`. Build the CLI
to one of those and reopen the panel. It does not need a shell restart, because
the panel checks again when it opens.

### Clicking a command does nothing

The CLI reports why and the panel shows the line in red. The usual causes are:

- The name in the list has changed since the panel read it. Reopen the panel;
  it re-reads the file.
- No terminal was found. Run `oshelly doctor`; it names the terminal it would
  use and fails when there is none.
- The terminal opens and closes immediately. That is the command exiting, not
  the launcher failing: the wrapper keeps the terminal open only after the
  command returns, and a command that replaces the shell or closes its own
  window can skip that step.

### The command runs, but in the wrong directory

There is no working directory to inherit from a bar click. On Omarchy, the CLI
uses `omarchy-launch-terminal`, which starts the terminal in the active
terminal's directory when it can, and in `$HOME` otherwise. Other terminals use
their own default. Use absolute paths in the config when it matters.

### The Edit button does nothing

The panel shows the reason in red. Run `oshelly doctor` in a terminal; it
prints the editor it would use. If that is not the one you want, set
`OSHELLY_EDITOR` in the environment the shell starts in, the same way as
`OSHELLY_TERMINAL`.

### A line is refused

The panel shows the line number and the reason. The common ones are a missing
colon, an empty name, an empty command, and two commands with the same name.
Fix the line and reopen the panel; no restart is needed.

## Design notes

- The panel runs one program and owns none of the behaviour. It reads a list
  with `list --json`, draws it, and sends a name with `run` or a setting with
  `set close`. The config parser and the terminal selection live in one place,
  so the panel and the macOS app cannot drift.
- The panel builds an argv array and runs no shell. A name with a space or a
  quote cannot become a second command on the way to the CLI.
- The panel inherits the session environment. That is the opposite of the
  odisplay panel, and it is deliberate: a terminal cannot draw without
  `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and the rest, while `ddcutil` needs none
  of them.
- The CLI launches the terminal and exits. The panel is never held open for the
  length of an interactive command, and the command can be interactive.
- The wrapper keeps the terminal open after the command, so a failed script's
  error stays readable.
- The bar glyph is `U+F120` (`fa-terminal`) in JetBrainsMono Nerd Font. It is
  written as an escape because the glyph is in the private use area and does
  not survive being pasted into a source file as a literal character.

## License

MIT

[cli]: https://github.com/h1st0ry3D/oshelly-cli
[mac]: https://github.com/h1st0ry3D/oshelly-mac

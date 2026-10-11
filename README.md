# Dotfiles

One installer, two layouts, every distro we care about. `bin/install` is the only entry point — it walks you through a short wizard and does the right thing for your machine.

## Quick start

### Fresh Arch desktop

Prerequisites: fresh Arch install, bootloader configured, a user account created.

```sh
curl -fsSL https://raw.githubusercontent.com/kensand/dotfiles/main/bin/install | sudo -E bash
```

The wizard asks a few questions (layout, packages, dotfiles). Press Enter to accept the defaults — for a fresh Arch desktop that is: desktop layout, all packages, all dotfiles. Installs the full Sway/Wayland stack (pacman + AUR via paru), Node.js LTS via nvm, the pi coding agent, clones the repo into `$HOME`, sets up submodules, enables services, and sets the login shell to zsh.

Pass `DOTFILES_BRANCH=<branch>` in the environment to clone a branch other than `main`.

Log out and back in after.

### Headless / SSH-only host (any distro)

Debian, Ubuntu, Arch, Fedora, SUSE, Alpine — `bin/install` detects the package manager (apt, pacman, dnf, zypper, apk) and installs the right package names automatically.

From the laptop, one command pushes everything over SSH:

```sh
bin/tty-push root@10.0.0.7            # + --no-packages, --tailscale, --dry-run
bin/tty-push kenny@box.example -p 2222
bin/tty-push user@host -- --no-chsh   # anything after -- reaches install
```

On the host itself:

```sh
# Interactive wizard (the normal path)
curl -fsSL https://raw.githubusercontent.com/kensand/dotfiles/main/bin/install | bash

# Non-interactive: headless layout, all packages, no prompts
curl -fsSL https://raw.githubusercontent.com/kensand/dotfiles/main/bin/install \
  | sudo -E bash -s -- --mode headless

# Configs only, no packages (no root needed)
curl -fsSL https://raw.githubusercontent.com/kensand/dotfiles/main/bin/install \
  | bash -s -- --mode headless --no-packages

# As root without sudo -E (container, Alpine without sudo)
curl -fsSL https://raw.githubusercontent.com/kensand/dotfiles/main/bin/install \
  | bash -s -- --mode headless --user kenny
```

Offline / no route to GitHub:

```sh
bash /path/to/dotfiles/bin/install --source /path/to/dotfiles --mode headless
```

Any invocation takes `--no-chsh` (leave the login shell alone) and `--dry-run` (print every command, change nothing).

### Re-running on an existing system

```sh
sudo -E bash ~/bin/install --mode desktop              # everything (idempotent)
sudo -E bash ~/bin/install --mode desktop --no-dotfiles # just update packages
bash ~/bin/install --mode headless --no-packages        # just pull configs
```

### Uninstall

```sh
bin/install --uninstall   # removes the symlinks, restores backups from ~/.dotfiles-tty-backup/
```

## Wizard

When stdin is a TTY (terminal, `ssh`, `sudo -E bash`), the installer asks:

```
==> dotfiles install — answer a few questions (Enter keeps the default):
  1) desktop   Arch + Sway/Wayland, full install
  2) headless  TTY/SSH-only host, any distro
  layout [1]: 2
  install packages? [y]:
  install dotfiles (zsh + tmux configs)? [y]:
```

Piped runs (`curl | bash` with no TTY) skip the wizard and use defaults: `desktop` layout, packages on, dotfiles on. Override with flags — `--mode headless`, `--no-packages`, `--no-dotfiles`.

## Distros

| Distro family | Package manager | Notes |
| ------------- | --------------- | ----- |
| Arch Linux    | pacman          | desktop + headless; AUR via paru for desktop |
| Debian / Ubuntu | apt           | `fd` → `fd-find`, `man-pages` → `manpages` |
| Fedora / RHEL | dnf             | `fd` → `fd-find` |
| SUSE          | zypper          | — |
| Alpine        | apk             | `man-db` → `busybox-extra` (BusyBox has `man` built-in); `btop` may be absent on slim images and is skipped with a warning; requires `bash` (run `apk add bash curl` first on a bare image) |

## Wallpaper / theming

`bin/chwall` fetches the top-of-day image from a subreddit (default `r/earthporn`, pass one to override), downloads the full-res original, regenerates the `wal` color scheme, and sets the Sway wallpaper — **no credentials required** (uses the public RSS feed).

```sh
~/bin/chwall                 # default subreddit
~/bin/chwall wallpapers      # a different subreddit
```

It's invoked on Sway startup via `~/.config/sway/config`.

## What the tty config does

| Behaviour | Detail |
| --------- | ------ |
| Non-interactive shells | Returns immediately, so `ssh host cmd`, `scp`, `rsync`, and `sftp` never touch any of this |
| tmux on SSH login | `exec tmux new-session -As ssh` — reconnecting lands back in the same session; `Ctrl-b d` detaches |
| Skips tmux when | inside tmux/screen, `TERM=dumb`, a forced command, tmux absent, or `DOTFILES_TMUX_AUTOATTACH=0` |
| Prompt / plugins | stock oh-my-zsh: `robbyrussell`, `plugins=(git history-substring-search)`, nothing desktop-specific |
| Self-update | backgrounded at startup, at most every 13 days, `git fetch` + fast-forward only, lockfile with stale-lock recovery, skipped on a dirty or ahead tree; one line of notice on the next shell |
| Opt out | `DOTFILES_UPDATE_DISABLE=1`, `DOTFILES_UPDATE_DAYS=n`, `DOTFILES_UPDATE_MODE=notify` (fetch + tell, never merge) |
| Manual | `~/.dotfiles/tty/update.sh run` \| `status` \| `check` |
| No `export TERM=…` | forcing TERM lies about where you connected from and costs 256-colour/truecolour inside tmux and vim |

Machine-specific paths (nvm, deno, Android SDK, JetBrains Toolbox, personal aliases) live in `~/.zshrc.local`, which is git-ignored on every machine and sourced last — see `tty/zshrc.local.example`. Extra oh-my-zsh plugins go in `~/.zshenv` (read before `.zshrc`), since oh-my-zsh has already read `$plugins` by the time the local file runs.

On the desktop, `~/.zshrc` is a one-line `source "$HOME/tty/zshrc"`, so editing `tty/zshrc` changes this laptop and every SSH host at once. That is deliberate: the laptop is where the config gets tested.

## What's in here

| Path | Purpose |
| ---- | ------- |
| `tty/` | Shared zsh + tmux config for headless hosts (and the desktop's real shell config) |
| `tty/update.sh` | Self-update: 13-day cooldown, fast-forward only, lockfile, one-line notice |
| `.config/sway/` | Sway window manager config |
| `.config/waybar/` | Waybar panel config |
| `.config/fuzzel/` | App launcher |
| `.config/way-displays/` | Display manager (external monitor layouts) |
| `.config/systemd/user/` | User systemd services |
| `.config/Daily-Reddit-Wallpaper/` | Holds the current wallpaper image |
| `.config/oh-my-zsh/` | Submodule — zsh framework |
| `.local/share/konsole/` | Konsole terminal profiles |
| `.zshrc`, `.zsh_aliases` | Zsh config (`~/.zshrc` is a shim onto `tty/zshrc`; `~/.zshrc.local` is untracked) |
| `.vimrc` | Vim config |
| `.tmux.conf` | Tmux config (desktop; headless hosts get `tty/tmux.conf`) |
| `bin/` | Custom scripts (incl. `chwall` wallpaper/theming) |
| `bin/install` | **The installer** — one script, two layouts, every distro |
| `bin/tty-push` | Push `tty/` + installer to a host over SSH and run it there |

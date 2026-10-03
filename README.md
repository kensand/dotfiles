# Dotfiles

Arch Linux + Sway/Wayland desktop setup, plus a headless bundle for TTY/SSH-only hosts. Both layouts share one shell config: `tty/zshrc`.

## Setup (blank system)

Prerequisites: fresh Arch install, bootloader configured, a user account created.

```sh
curl -sL https://github.com/kensand/dotfiles/raw/main/bin/setup.sh | sudo -E bash
```

This installs packages (including Node.js LTS via nvm and paru from the AUR), clones dotfiles into `$HOME`, sets up submodules, enables services, and sets your shell to zsh. Pass `DOTFILES_BRANCH=<branch>` in the environment to clone a branch other than `main`.

Log out and back in after.

## Wallpaper / theming

`bin/chwall` fetches the top-of-day image from a subreddit (default `r/earthporn`, pass one to override), downloads the full-res original, regenerates the `wal` color scheme, and sets the Sway wallpaper — **no credentials required** (uses the public RSS feed).

```sh
~/bin/chwall                 # default subreddit
~/bin/chwall wallpapers      # a different subreddit
```

It's invoked on Sway startup via `~/.config/sway/config`.

## Re-running on an existing system

```sh
sudo -E bash ~/bin/setup.sh              # everything (idempotent)
sudo -E bash ~/bin/setup.sh --packages   # just update packages
sudo -E bash ~/bin/setup.sh --dotfiles   # just pull dotfiles + submodules
```

## Headless / SSH-only hosts

`tty/` holds a small, default-by-design shell setup for machines you only ever reach over SSH — no sway, waybar, fuzzel, konsole, fonts, wallpaper tooling, or AUR. `bin/setup-tty.sh` installs it; `bin/tty-push` runs that installer on another machine.

From this laptop, one command:

```sh
bin/tty-push root@10.0.0.7            # + --no-packages, --tailscale, --dry-run
bin/tty-push kenny@box.example -p 2222
bin/tty-push user@host -- --no-chsh   # anything after -- reaches setup-tty.sh
```

It tars `tty/` + the installer to `~/.dotfiles-tty-bundle`, so the target needs only a POSIX shell and `tar` — no curl, git, or GitHub access. It then asks the target whether *it* can reach the repo: if yes it sparse-clones (that is what enables self-update), if no it installs from the bundle and says so. Install bash on a bare Alpine image is handled first, since the installer itself is bash.

On the host itself (Debian/Ubuntu/Arch/Fedora/SUSE/Alpine — pacman, apt, dnf, zypper, apk are all detected):

```sh
BRANCH=main   # the canonical branch; framework-13 is the old name for the same line
# as root, for $SUDO_USER; or as the user, where sudo is used for packages only
curl -fsSL "https://github.com/kensand/dotfiles/raw/$BRANCH/bin/setup-tty.sh" | bash
# offline / no route to GitHub: point it at a checkout or an unpacked bundle
bash /path/to/dotfiles/bin/setup-tty.sh --source /path/to/dotfiles
```

What it does: installs zsh, tmux, git, curl, vim, a few terminal tools and `ca-certificates`; clones oh-my-zsh to `~/.oh-my-zsh` unless one already exists; sparse-clones this repo to `~/.dotfiles` (**`tty/` + this script only** — the desktop's committed binaries in `bin/` stay behind, ~200 KB instead of 40 MB); symlinks `~/.zshrc` and `~/.tmux.conf` (previous files are moved to `~/.dotfiles-tty-backup/`, never deleted); sets the login shell to zsh; then verifies from the outside that `~/.zshrc` parses, tmux loads, and reports the login shell. `--dry-run` shows every command, `--uninstall` restores the backups.

If `$HOME` *is* this repo (the desktop layout), it adopts that instead of cloning a second copy and leaves the tracked `~/.zshrc` and `~/.tmux.conf` alone.

### What the tty config does

| Behaviour | Detail |
| ----------- | -------- |
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
| ------ | --------- |
| `tty/` | Shared zsh + tmux config for headless hosts (and the desktop's real shell config) |
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
| `bin/` | Custom scripts (incl. `chwall` wallpaper/theming + this setup script) |
| `bin/setup.sh` | Desktop installer (Arch + sway, AUR, nvm) |
| `bin/setup-tty.sh` | Headless installer (any distro, no display server) |
| `bin/tty-push` | Push `tty/` to a host over SSH and install it there |

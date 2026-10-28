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

Any invocation takes `--no-chsh` (leave the login shell alone), `--no-pi` (skip the
pi coding agent + f creds section) and `--dry-run` (print every command, change nothing).

### Termux (Android)

Termux is detected from the environment (`$PREFIX` under `.../com.termux/`, or
`ANDROID_ROOT` plus `pkg` on PATH), so the same one-liner is the install path.
There is no root here and there must not be one: `pkg` refuses to run as root,
so the installer never prefixes `sudo` on Termux even though termux-tools ships
a `sudo(1)`.

```sh
curl -fsSL https://raw.githubusercontent.com/kensand/dotfiles/main/bin/install | bash
```

What differs on Android:

| Normal host | Termux |
| ----------- | ------ |
| `/etc/os-release`, `sudo` | environmental detection, `$SUDO` always empty |
| `apt` / `pacman` / `dnf` | `pkg install -y` (apt + dpkg pinned to `$PREFIX`) |
| `getent passwd` for `$HOME` | `$HOME` (`/data/data/com.termux/files/home`); `$USER` is empty and there is no passwd database |
| `chsh -s $(command -v zsh)` edits `/etc/passwd` | `chsh -s zsh` writes the `~/.termux/shell` symlink the app reads at session start |
| `systemctl` | absent; every service step is skipped |

The layout is always `headless`: Termux has no KMS/DRM master, no systemd user
session and no display server, so `--mode desktop` stops with an error instead
of installing a Sway stack that could never start. `man-db`, `man-pages`, `man`
and `btop` are not in the Termux repos and are skipped by name (`man` and `vi`
come from busybox). The tmux-on-SSH-login hook stays inert: inside Termux there
is no `SSH_TTY`.

Configs only, no prompts, no shell change:

```sh
bash bin/install --mode headless --no-packages --no-chsh --no-pi --source /path/to/dotfiles
```

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
| Termux (Android) | `pkg` (apt + dpkg in `$PREFIX`) | headless layout only; no root, sudo, systemd or `/etc/passwd`; `man-db`/`man-pages`/`man`/`btop` skipped by name; login shell = `~/.termux/shell` |

## CPU architecture

`bin/install` reads `uname -m` and, on aarch64, `/proc/device-tree/compatible`.

| Arch | Behaviour |
| ---- | --------- |
| x86_64 | Full install as before: `linux`/`linux-headers`, `amd-ucode`, `efibootmgr`, `vulkan-radeon`, all AUR packages |
| aarch64 | No microcode blobs, no `efibootmgr`, **kernel packages untouched** (swapping a vendor/BSP kernel for mainline is the usual way to make a board unbootable — install your board's kernel explicitly). Graphics chosen from the SoC. AUR repos swapped for arm-built ones (below) and packages installed one-by-one so one failure does not abort the set |
| other | Warns; the desktop list is only validated on x86_64/aarch64 |

### Rockchip graphics

There is no AMD/Intel GPU here — the driver depends on the Mali generation, so it
is picked from the device tree:

| SoC | GPU | Stack |
| --- | --- | ----- |
| RK3588 / 3588S | Mali-G610 (Valhall) | **panthor** kernel driver + Mesa with panthor support. Needs kernel 6.13+ or a BSP with the backport, plus the proprietary `/usr/lib/firmware/mali_csffw.bin` blob (from `linux-firmware`). `mesa-panfork` does *not* work on Valhall |
| RK3399 | Mali-T860 (Midgard) | `mesa` panfrost |
| RK3566 / RK3568 | Mali-G52 (Bifrost) | `mesa` panfrost |

The installer reports what it found rather than assuming: it checks `/proc/devices`
for a `panthor`/`panfrost` DRM node and warns if `mali_csffw.bin` is missing, since
either condition means no GPU acceleration despite packages installing cleanly.

### AUR on aarch64

Vanilla AUR is unusable on arm: most PKGBUILDs declare `arch=('x86_64')` or download
prebuilt x86 tarballs. The installer adds two arm-built repos to `pacman.conf`
instead of compiling on-device (a full AUR build on an SBC takes hours):

```
[archlinuxcn]  Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
[7ji]          Server = https://github.com/7Ji/archrepo/releases/download/$arch
```

Anything still missing is skipped with a warning. Note `jetbrains-toolbox` is
never attempted on arm — upstream ships x86_64 binaries only.

The sway config guards its optional autostarts (`way-displays`, `sov`, `iwgtk`,
`element-desktop`) with `command -v`, so a host without them starts normally.

## Wallpaper / theming

`bin/chwall` fetches the top-of-day image from a subreddit (default `r/earthporn`, pass one to override), downloads the full-res original, regenerates the `wal` color scheme, and sets the Sway wallpaper — **no credentials required** (uses the public RSS feed).

```sh
~/bin/chwall                 # default subreddit
~/bin/chwall wallpapers      # a different subreddit
```

It's invoked on Sway startup via `~/.config/sway/config`.

## Portal stack (desktop)

Wayland apps don't draw their own file pickers, share screens, or open URIs — they ask **xdg-desktop-portal**, which forwards each request to a backend implementation. Getting this wrong is invisible: the app just shows no dialog and logs nothing.

Two files own it:

- `~/.config/xdg-desktop-portal/portals.conf` — which backend serves which interface. `default=kde` (so FileChooser gets the KDE/Dolphin picker), `wlr` for ScreenCast/Screenshot, `Inhibit=none` so Firefox uses Wayland's idle-inhibit instead of a `org.gnome.SessionManager` call Sway doesn't implement.
- `~/.config/environment.d/qt-wayland.conf` — `QT_QPA_PLATFORM=wayland`.

The non-obvious part: portal backends are **dbus-activated by `user@1000.service`, which starts with no `DISPLAY` or `WAYLAND_DISPLAY`**. Left alone, every backend aborts at startup — `xdg-desktop-portal-kde` with `could not connect to display` / `Could not load the Qt platform plugin "xcb"`, `xdg-desktop-portal-gtk` with `cannot open display:` — and then hits `start-limit-hit` so it stops even trying. Sway therefore runs, before starting any portal unit:

```swayconfig
exec systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE QT_QPA_PLATFORM
```

Without that `import-environment`, nothing in the portal stack can ever launch from a dbus activation, no matter what `portals.conf` says. Sway also `stop`s then `start`s the units so a daemon dbus-activated during boot can't coexist with the session one and steal the wlr backend's bus name (`failed to acquire service name: File exists`).

Diagnose with:

```sh
systemctl --user show-environment | grep -E 'DISPLAY|WAYLAND'   # must not be empty
journalctl --user --since today | grep -iE 'portal|cannot open display'
busctl --user list | grep impl.portal.desktop                   # who owns each backend
```

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
| `.config/xdg-desktop-portal/portals.conf` | Portal backend routing (kde default, wlr for capture) |
| `.config/environment.d/qt-wayland.conf` | `QT_QPA_PLATFORM=wayland`, keeps Qt portal services off xcb |
| `.config/systemd/user/xdg-desktop-portal.service.d/` | Drop-in ordering the KDE backend behind the portal daemon |
| `.config/sway/` | Sway window manager config |
| `.config/waybar/` | Waybar panel config |
| `.config/fuzzel/` | App launcher |
| `.config/way-displays/` | Display manager (external monitor layouts) |
| `.config/systemd/user/` | User systemd services |
| `.cache/chwall/` | Holds the current wallpaper image (chwall cache) |
| `.config/oh-my-zsh/` | Submodule — zsh framework |
| `.local/share/konsole/` | Konsole terminal profiles |
| `.zshrc`, `.zsh_aliases` | Zsh config (`~/.zshrc` is a shim onto `tty/zshrc`; `~/.zshrc.local` is untracked) |
| `.vimrc` | Vim config |
| `.tmux.conf` | Tmux config (desktop; headless hosts get `tty/tmux.conf`) |
| `bin/` | Custom scripts (incl. `chwall` wallpaper/theming) |
| `bin/install` | **The installer** — one script, two layouts, every distro |
| `bin/tty-push` | Push `tty/` + installer to a host over SSH and run it there |

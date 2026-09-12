# Dotfiles

Arch Linux + Sway/Wayland desktop setup.

## Setup (blank system)

Prerequisites: fresh Arch install, bootloader configured, a user account created.

```sh
curl -sL https://github.com/kensand/dotfiles/raw/framework-13/bin/setup.sh | sudo -E bash
```

This installs packages (including Node.js LTS via nvm and paru from the AUR), clones dotfiles into `$HOME`, sets up submodules, enables services, and sets your shell to zsh.

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

## What's in here

| Path | Purpose |
| ------ | --------- |
| `.config/sway/` | Sway window manager config |
| `.config/waybar/` | Waybar panel config |
| `.config/fuzzel/` | App launcher |
| `.config/way-displays/` | Display manager (external monitor layouts) |
| `.config/systemd/user/` | User systemd services |
| `.config/Daily-Reddit-Wallpaper/` | Holds the current wallpaper image |
| `.config/oh-my-zsh/` | Submodule — zsh framework |
| `.local/share/konsole/` | Konsole terminal profiles |
| `.zshrc`, `.zsh_aliases` | Zsh config |
| `.vimrc` | Vim config |
| `.tmux.conf` | Tmux config |
| `bin/` | Custom scripts (incl. `chwall` wallpaper/theming + this setup script) |

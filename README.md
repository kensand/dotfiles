# Dotfiles

Arch Linux + Sway/Wayland desktop setup.

## Setup (blank system)

Prerequisites: fresh Arch install, bootloader configured, a user account created,
and SSH key added to your Forgejo so the repo can be fetched.

```sh
cd ~ && git init && git remote add origin git@forgejo.kensand.net:kensand/dotfiles.git && git pull origin framework-13 && git submodule update --init --recursive && git branch -M framework-13 && sudo -E bash bin/setup.sh --dotfiles
```

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
| `.config/Daily-Reddit-Wallpaper/` | Submodule — wallpaper rotation |
| `.config/oh-my-zsh/` | Submodule — zsh framework |
| `.local/share/konsole/` | Konsole terminal profiles |
| `.zshrc`, `.zsh_aliases` | Zsh config |
| `.vimrc` | Vim config |
| `.tmux.conf` | Tmux config |
| `bin/` | Custom scripts + this setup script |

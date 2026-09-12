#!/bin/bash
# Arch Linux + Sway setup script
# Idempotent: safe to run multiple times. Skips what's already done.
#
# Handles:
#   1. System packages (pacman + AUR via paru)
#   2. Dotfiles repo clone/checkout + submodules
#   3. Services and user setup
#
# Usage:
#   sudo -E bash setup.sh              # full setup (packages + dotfiles)
#   sudo -E bash setup.sh --packages   # packages only
#   sudo -E bash setup.sh --dotfiles   # dotfiles only
#
# Assumes: fresh Arch install, base system + bootloader configured,
#          a user account exists.

set -euo pipefail

DOTFILES_REPO="git@github.com:kensand/dotfiles.git"
DOTFILES_DIR="$HOME"
USER_NAME="${SUDO_USER:-$USER}"

info() { echo "==> $1"; }
skip() { echo "==> [skip] $1"; }
warn() { echo "==> WARNING: $1"; }

# Parse args
DO_PACKAGES=true
DO_DOTFILES=true
for arg in "$@"; do
	case "$arg" in
	--packages) DO_DOTFILES=false ;;
	--dotfiles) DO_PACKAGES=false ;;
	-h | --help)
		echo "Usage: sudo -E bash setup.sh [--packages|--dotfiles]"
		exit 0
		;;
	esac
done

# ════════════════════════════════════════════════════════════════
# PACKAGES
# ════════════════════════════════════════════════════════════════
if $DO_PACKAGES; then
	[[ $EUID -ne 0 ]] && {
		echo "Packages section requires root (sudo -E)." >&2
		exit 1
	}

	# ────────────────────────────────────────────────────────────
	# 1. System essentials
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		base
		base-devel
		linux
		linux-headers
		linux-firmware
		amd-ucode
		efibootmgr
		openssh
		systemd-resolvconf
		man-db
		man-pages
		wget
		unzip
		zip
		bc
		screen
		git
		zsh
		vim
		nano
		btop
		htop
		lsof
		lshw
		usbutils
		smartmontools
		fd
		ripgrep
		tree
		neovim
		jq
	)
	info "Installing system packages..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 2. Sway / Wayland desktop
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		sway
		swaybg
		swaylock
		swayidle
		swaync
		waybar
		fuzzel
		wofi
		grim
		slurp
		wl-clipboard
		swappy
		libinput-gestures
		brightnessctl
		sddm
		i3-wm
		dmenu
	)
	info "Installing Sway/Wayland packages..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 3. Audio (Pipewire stack)
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		pipewire
		pipewire-pulse
		pipewire-alsa
		pipewire-jack
		wireplumber
		gst-plugin-pipewire
		pavucontrol
		flite1
	)
	info "Installing Pipewire audio stack..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 4. Networking
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		iwd
		iwgtk
		dnsmasq
		wireguard-tools
		tailscale
		blueman
	)
	info "Installing networking packages..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 5. Applications
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		firefox
		chromium
		thunderbird
		element-desktop
		signal-desktop
		discord
		konsole
		kitty
	)
	info "Installing applications..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 6. Desktop portal & session
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		xdg-desktop-portal
		xdg-desktop-portal-wlr
		xdg-desktop-portal-gtk
		xdg-utils
		gnome-keyring
		qt6-wayland
	)
	info "Installing desktop portal packages..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 7. Fonts
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		ttf-fira-code
		woff2-font-awesome
		ttf-font-awesome-4
	)
	info "Installing fonts..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 8. Python & scripting
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		python
		python-pip
		python-pywal
	)
	info "Installing Python packages..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 9. Utilities
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		fdupes
		progress
		pv
		ncdu
		flameshot
		simple-scan
		gvfs-mtp
		exfat-utils
		squashfuse
		sshfs
	)
	info "Installing utilities..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 10. Graphics (AMD)
	# ────────────────────────────────────────────────────────────
	info "Installing AMD graphics drivers..."
	pacman -S --noconfirm --needed vulkan-radeon

	# ────────────────────────────────────────────────────────────
	# 11. AUR packages (paru)
	# ────────────────────────────────────────────────────────────
	if ! command -v paru &>/dev/null; then
		info "Bootstrapping paru from AUR..."
		sudo -u "$USER_NAME" bash -c '
			set -e
			tmpdir=$(mktemp -d)
			cd "$tmpdir"
			git clone --depth 1 https://aur.archlinux.org/paru.git
			cd paru
			makepkg -si --noconfirm
			rm -rf "$tmpdir"
		'
	else
		skip "paru already installed"
	fi

	info "Installing AUR packages..."
	sudo -u "$USER_NAME" paru -S --noconfirm --needed \
		way-displays \
		grimshot \
		pw-volume \
		sov \
		jetbrains-toolbox

	# ────────────────────────────────────────────────────────────
	# 12. Services
	# ────────────────────────────────────────────────────────────
	info "Enabling system services..."
	systemctl enable sddm
	systemctl enable iwd
	systemctl enable tailscaled
fi

# ════════════════════════════════════════════════════════════════
# DOTFILES
# ════════════════════════════════════════════════════════════════
if $DO_DOTFILES; then
	# Run as the user, not root
	if [[ $EUID -eq 0 ]]; then
		sudo -u "$USER_NAME" bash "$0" --dotfiles
		exit $?
	fi

	info "Setting up dotfiles..."

	# ────────────────────────────────────────────────────────────
	# Clone or update the dotfiles repo
	# ────────────────────────────────────────────────────────────
	if [[ -d "$DOTFILES_DIR/.git" ]]; then
		skip "Dotfiles repo already exists, pulling latest..."
		cd "$DOTFILES_DIR"
		git pull --ff-only
	else
		info "Initializing dotfiles repo in $DOTFILES_DIR..."
		cd "$DOTFILES_DIR"
		git init
		git remote add origin "$DOTFILES_REPO"
		git pull origin framework-13
		git branch -M framework-13
	fi

	# ────────────────────────────────────────────────────────────
	# Initialize submodules
	# ────────────────────────────────────────────────────────────
	info "Initializing submodules..."
	git submodule update --init --recursive

	# ────────────────────────────────────────────────────────────
	# Set up oh-my-zsh
	# ────────────────────────────────────────────────────────────
	# .zshrc expects ZSH="$HOME/.config/oh-my-zsh"
	# The submodule lives at .config/oh-my-zsh already — just make sure it's there.
	if [[ ! -d "$HOME/.config/oh-my-zsh" ]]; then
		warn "oh-my-zsh submodule missing. Run: git submodule update --init"
	fi

	# ────────────────────────────────────────────────────────────
	# Set user shell to zsh
	# ────────────────────────────────────────────────────────────
	current_shell=$(getent passwd "$USER_NAME" | cut -d: -f7)
	if [[ "$current_shell" != "/usr/bin/zsh" ]]; then
		info "Setting shell to zsh..."
		chsh -s /usr/bin/zsh "$USER_NAME"
	else
		skip "Shell already zsh"
	fi

	# ────────────────────────────────────────────────────────────
	# Enable libinput-gestures (trackpad gestures)
	# ────────────────────────────────────────────────────────────
	if systemctl list-unit-files 2>/dev/null | grep -q libinput-gestures; then
		systemctl enable --now libinput-gestures.service 2>/dev/null || true
	fi

	# ────────────────────────────────────────────────────────────
	# Create wal cache dir
	# ────────────────────────────────────────────────────────────
	if [[ ! -d "$HOME/.cache/wal" ]]; then
		info "Creating ~/.cache/wal..."
		mkdir -p "$HOME/.cache/wal/schemes"
	fi

	# ────────────────────────────────────────────────────────────
	# Enable systemd user services from dotfiles
	# ────────────────────────────────────────────────────────────
	if [[ -f "$HOME/.config/systemd/user/xdg-desktop-portal.service" ]]; then
		info "Enabling xdg-desktop-portal user service..."
		cp "$HOME/.config/systemd/user/xdg-desktop-portal.service" \
			"$HOME/.config/systemd/user/" 2>/dev/null || true
		systemctl --user daemon-reload
		systemctl --user enable xdg-desktop-portal.service
	fi

	info "Dotfiles setup complete!"
fi

# ════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════
info "Done!"
echo ""
echo "Next steps:"
echo "  1. Log out and back in (or reboot) to get your new shell + services"
echo "  2. If using Sway: make sure you're on a Wayland session in SDDM"
echo "  3. Run 'wal -i <image>' once to generate your color scheme"
echo "  4. The waybar mediaplayer script needs to be in ~/.config/waybar/"

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

DOTFILES_REPO="https://github.com/kensand/dotfiles.git"
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
	)
	info "Installing Pipewire audio stack..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 4. Networking
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		iwd
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
	)
	info "Installing fonts..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 8. Python & scripting
	# ────────────────────────────────────────────────────────────
	pacman_pkgs=(
		python
		python-pip
		nvm
	)
	info "Installing Python packages..."
	pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

	# ────────────────────────────────────────────────────────────
	# 8b. Node.js LTS (via nvm)
	# ────────────────────────────────────────────────────────────
	# nvm is a shell function; load it, then install LTS if not present.
	if [[ -f /usr/share/nvm/init-nvm.sh ]]; then
		if ! sudo -u "$USER_NAME" bash -c 'source /usr/share/nvm/init-nvm.sh; nvm version --lts >/dev/null 2>&1'; then
			info "Installing Node.js LTS via nvm..."
			sudo -u "$USER_NAME" bash -c 'source /usr/share/nvm/init-nvm.sh; nvm install --lts && nvm alias default lts/*'
		else
			skip "Node.js LTS already installed"
		fi
	else
		warn "nvm init script not found; skipping Node.js LTS install"
	fi

	# ────────────────────────────────────────────────────────────
	# 8c. pi coding agent (npm global, needs Node.js from 8b)
	# ────────────────────────────────────────────────────────────
	# Install as the user. --ignore-scripts per pi's docs. The dotfiles repo
	# tracks only ~/.pi/agent/settings.json (see .pi/agent/.gitignore); auth,
	# mcp, models, sessions, and caches stay local and are never committed.
	if ! sudo -u "$USER_NAME" bash -c 'source /usr/share/nvm/init-nvm.sh; command -v pi >/dev/null 2>&1'; then
		info "Installing pi coding agent (npm global)..."
		sudo -u "$USER_NAME" bash -c 'source /usr/share/nvm/init-nvm.sh; npm install -g --ignore-scripts @earendil-works/pi-coding-agent'
	else
		skip "pi coding agent already installed"
	fi

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
	# paru is built from source (needs cargo, from base-devel/rust). We build the
	# package as the user (makepkg) and install it as root (pacman -U), because a
	# normal user has no passwordless sudo for the -i step.
	if ! command -v paru &>/dev/null; then
		info "Bootstrapping paru from AUR..."
		# Ensure build deps are present
		pacman -S --noconfirm --needed base-devel cargo git
		# Build the package as the user (makepkg) and install it as root (pacman -U),
		# because a normal user has no passwordless sudo for the -i step.
		# The build dir must be created *by the user* (via mktemp inside sudo -u) so
		# it is user-owned and writable — a root-created mktemp -d dir is root-owned
		# and the user cannot write into it ("could not create work tree dir: 
		# permission denied").
		build_dir=$(sudo -u "$USER_NAME" mktemp -d)
		sudo -u "$USER_NAME" bash -c "
			set -e
			cd '$build_dir'
			git clone --depth 1 https://aur.archlinux.org/paru.git
			cd paru
			makepkg -s --noconfirm
		"
		# Install the built package (and its debug split) as root
		pacman -U --noconfirm "$build_dir"/paru/*.pkg.tar.zst
		sudo rm -rf "$build_dir"
	else
		skip "paru already installed"
	fi

	info "Installing AUR packages..."
	sudo -u "$USER_NAME" paru -S --noconfirm --needed \
		way-displays \
		grimshot \
		pw-volume \
		sov \
		libinput-gestures \
		iwgtk \
		python-pywal \
		ttf-font-awesome-4 \
		jetbrains-toolbox

	# ────────────────────────────────────────────────────────────
	# 12. Services
	# ────────────────────────────────────────────────────────────
	info "Enabling system services..."
	systemctl enable sddm
	systemctl enable iwd
	systemctl enable tailscaled

	# ────────────────────────────────────────────────────────────
	# 13. Set user shell to zsh
	# ────────────────────────────────────────────────────────────
	current_shell=$(getent passwd "$USER_NAME" | cut -d: -f7)
	if [[ "$current_shell" != "/usr/bin/zsh" ]]; then
		info "Setting shell to zsh..."
		chsh -s /usr/bin/zsh "$USER_NAME"
	else
		skip "Shell already zsh"
	fi
fi

# ════════════════════════════════════════════════════════════════
# DOTFILES
# ════════════════════════════════════════════════════════════════
if $DO_DOTFILES; then
	info "Setting up dotfiles..."
	USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

	# ────────────────────────────────────────────────────────────
	# Clone or update the dotfiles repo (as user, in their home)
	# ────────────────────────────────────────────────────────────
	if [[ -d "$USER_HOME/.git" ]]; then
		skip "Dotfiles repo already exists, pulling latest..."
		sudo -u "$USER_NAME" git -C "$USER_HOME" pull --ff-only
	else
		# Clone to a temp dir first: $HOME is non-empty on a fresh Arch install
		# (stock .bashrc/.bash_profile/.bash_logout) and would make `git pull` into
		# an in-place `git init` abort with "untracked files would be overwritten".
		# We clone cleanly, then move the working tree + .git into $HOME, backing
		# up any existing files that collide so nothing is lost.
		info "Setting up dotfiles repo in $USER_HOME..."
		sudo -u "$USER_NAME" bash -c '
			set -e
			repo_url="$1"; home="$2"
			tmpdir=$(mktemp -d)
			trap "rm -rf $tmpdir" EXIT
			git clone --quiet --branch framework-13 "$repo_url" "$tmpdir/repo"
			cd "$tmpdir/repo"
			git submodule update --init --recursive
			# Move every top-level path (files and .git) into $HOME. If a file of
			# the same name already exists there (e.g. stock .bashrc), back it up
			# first so nothing is lost.
			mkdir -p "$home/.dotfiles-backup"
			shopt -s dotglob nullglob
			for item in *; do
				dest="$home/$item"
				if [ -e "$dest" ]; then
					mv "$dest" "$home/.dotfiles-backup/$item"
				fi
				mv "$item" "$dest"
			done
		' _ "$DOTFILES_REPO" "$USER_HOME"
	fi

	# ────────────────────────────────────────────────────────────
	# Konsole profiles
	# ────────────────────────────────────────────────────────────
	if [[ -d "$USER_HOME/.local/share/konsole" ]]; then
		skip "Konsole profiles already in place"
	else
		info "Setting up konsole profiles..."
		sudo -u "$USER_NAME" mkdir -p "$USER_HOME/.local/share/konsole"
		sudo -u "$USER_NAME" cp "$USER_HOME/.local/share/konsole/Linux.colorscheme" \
			"$USER_HOME/.local/share/konsole/Profile 1.profile" \
			"$USER_HOME/.local/share/konsole/bookmarks.xml" \
			"$USER_HOME/.local/share/konsole/" 2>/dev/null || true
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
	if [[ ! -d "$USER_HOME/.cache/wal" ]]; then
		info "Creating ~/.cache/wal..."
		sudo -u "$USER_NAME" mkdir -p "$USER_HOME/.cache/wal/schemes"
	fi

	# ────────────────────────────────────────────────────────────
	# Enable systemd user services from dotfiles
	# ────────────────────────────────────────────────────────────
	if [[ -f "$USER_HOME/.config/systemd/user/xdg-desktop-portal.service" ]]; then
		info "Enabling xdg-desktop-portal user service..."
		sudo -u "$USER_NAME" systemctl --user daemon-reload 2>/dev/null || true
		sudo -u "$USER_NAME" systemctl --user enable xdg-desktop-portal.service 2>/dev/null || true
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

#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# TTY / SSH-only host setup — the headless counterpart of bin/setup.sh.
#
# Installs the tty/ bundle (default-by-design zsh + tmux configs) and the
# packages a terminal-only host needs. Nothing here wants a display server: no
# sway, waybar, fuzzel, konsole, fonts, or wallpaper tooling, and no AUR build.
#
# It is idempotent and it will not fight the desktop setup: if $HOME already is
# this repo (the laptop layout), it adopts that instead of cloning a second copy,
# and it leaves the tracked desktop .zshrc and .tmux.conf alone.
#
# Usage:
#   bash bin/setup-tty.sh                  # as the user who will log in
#   sudo -E bash bin/setup-tty.sh          # as root; targets $SUDO_USER's home
#   bash bin/setup-tty.sh --dry-run        # print what would happen, change nothing
#   bash bin/setup-tty.sh --uninstall      # undo the links, restore backups
#   bin/tty-push user@host                 # run this ON a remote host, from here
#
# Flags:
#   --packages      packages only
#   --dotfiles      configs only
#   --no-packages   skip the package step (needs no root)
#   --repo-url URL  clone source   [default https://github.com/kensand/dotfiles.git]
#   --branch NAME   branch to track [default: the branch this script came from]
#   --source DIR    offline: take tty/ from DIR (a repo checkout or a bundle) instead of cloning
#   --copy          copy into $HOME instead of symlinking to the repo
#   --no-chsh       do not switch the login shell to zsh
#   --tailscale     also install and enable tailscaled
#   --uninstall     remove the files this script linked and restore what it moved
#   -h, --help      this text
#
# What it does, in order:
#   1. packages (zsh, tmux, git, curl, and terminal tools) via the host's own
#      package manager — pacman, apt, dnf, zypper or apk
#   2. oh-my-zsh, cloned to ~/.oh-my-zsh if no install is already found
#   3. the dotfiles repo, sparse-cloned to ~/.dotfiles (tty/ plus this script,
#      so the 40 MB of binaries the desktop keeps in bin/ does not come along)
#   4. ~/.zshrc and ~/.tmux.conf symlinked into it, backups kept
#   5. login shell set to zsh; SSH logins then reattach to tmux via tty/zshrc
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES_REPO="https://github.com/kensand/dotfiles.git"
OMZ_REPO="https://github.com/robbyrussell/oh-my-zsh.git"
OMZ_BRANCH="master"

# The branch this script was read from, when it is inside the repo. Falling back
# to the default branch of the remote keeps 'curl | bash' working from a raw URL.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
GUESS_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[[ -n "$GUESS_BRANCH" && "$GUESS_BRANCH" != HEAD ]] || GUESS_BRANCH=""

REPO_URL="${DOTFILES_REPO_URL:-$DOTFILES_REPO}"
BRANCH="${DOTFILES_BRANCH:-$GUESS_BRANCH}"
SOURCE_DIR=""
COPY_FILES=false
NO_CHSH=false
WITH_TAILSCALE=false
DO_PACKAGES=true
DO_DOTFILES=true
DRY=false
UNINSTALL=false

info() { echo "==> $1"; }
skip() { echo "==> [skip] $1"; }
warn() { echo "==> WARNING: $1"; }
die() {
	echo "==> ERROR: $1" >&2
	exit 1
}

# Echoes the command instead of running it under --dry-run.
run() {
	if $DRY; then
		printf '  [dry] %s\n' "$*"
		return 0
	fi
	"$@"
}

trap 'echo "==> ERROR: setup-tty.sh failed at line $LINENO (last command exited $?). See above." >&2' ERR

# ─────────────────────────────────────────────────────────────────────────────
# Args
# ─────────────────────────────────────────────────────────────────────────────
need_arg() { [[ -n "${2:-}" ]] || die "$1 needs a value"; }

while [[ $# -gt 0 ]]; do
	case "$1" in
	--packages) DO_DOTFILES=false ;;
	--dotfiles) DO_PACKAGES=false ;;
	--no-packages) DO_PACKAGES=false ;;
	--copy) COPY_FILES=true ;;
	--no-chsh) NO_CHSH=true ;;
	--tailscale) WITH_TAILSCALE=true ;;
	--dry-run | -n) DRY=true ;;
	--uninstall) UNINSTALL=true ;;
	--repo-url)
		need_arg "$1" "${2:-}"
		REPO_URL="$2"
		shift
		;;
	--branch)
		need_arg "$1" "${2:-}"
		BRANCH="$2"
		shift
		;;
	--source)
		need_arg "$1" "${2:-}"
		SOURCE_DIR="$2"
		shift
		;;
	-h | --help)
		sed -n '2,/^# ─*$/p' "${BASH_SOURCE[0]}" | sed '1d;s/^# \{0,1\}//'
		exit 0
		;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
	shift
done

# ─────────────────────────────────────────────────────────────────────────────
# Who and where
# ─────────────────────────────────────────────────────────────────────────────
USER_NAME="${SUDO_USER:-${USER:-$(id -un)}}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || die "cannot find a home directory for $USER_NAME"

# Packages need root; the config work must NOT be done as root.
if [[ $EUID -eq 0 ]]; then
	SUDO=""
else
	if command -v sudo >/dev/null 2>&1; then
		SUDO="sudo"
	else
		SUDO=""
	fi
fi

# As the target user, whether or not we started as root. Containers set neither
# $USER nor $SUDO_USER, hence the id -un fallback above.
as_user() {
	if [[ $EUID -eq 0 && "$USER_NAME" != "$(id -un)" ]]; then
		have_cmd sudo ||
			die "running as root for $USER_NAME but sudo is missing; run this as $USER_NAME directly"
		sudo -u "$USER_NAME" "$@"
	else
		"$@"
	fi
}

DOTDIR="$USER_HOME/.dotfiles"
BACKUP_ROOT="$USER_HOME/.dotfiles-tty-backup"

info "tty setup starting (user: $USER_NAME, home: $USER_HOME)"
$DRY && info "dry run: nothing will change"

# ─────────────────────────────────────────────────────────────────────────────
# Package manager + package name mapping
# ─────────────────────────────────────────────────────────────────────────────
PKG=""
detect_pkg() {
	local id likes
	if [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		id=$(. /etc/os-release && echo "${ID:-}")
		likes=$(. /etc/os-release && echo "${ID_LIKE:-}")
	else
		id=""
		likes=""
	fi
	for c in $id $likes; do
		case "$c" in
		arch)
			PKG=pacman
			return
			;;
		debian | ubuntu)
			PKG=apt
			return
			;;
		fedora | rhel | centos | amzn)
			PKG=dnf
			return
			;;
		suse | opensuse*)
			PKG=zypper
			return
			;;
		alpine)
			PKG=apk
			return
			;;
		esac
	done
	# No usable os-release: trust whatever binary exists.
	local m
	for m in pacman apt-get dnf yum zypper apk xbps-install; do
		command -v "$m" >/dev/null 2>&1 && {
			case "$m" in
			pacman) PKG=pacman ;;
			apt-get) PKG=apt ;;
			dnf | yum) PKG=dnf ;;
			zypper) PKG=zypper ;;
			apk) PKG=apk ;;
			esac
			return
		}
	done
	PKG=""
}

# One canonical name per tool; some distros renamed them.
pkg_name() {
	case "$PKG:$1" in
	apt:fd | dnf:fd) echo fd-find ;;
	apt:man-pages) echo manpages ;;
	*) echo "$1" ;;
	esac
}

# Already on PATH? Used to skip what is there and to name what is missing.
have_cmd() {
	local c
	for c in "$@"; do command -v "$c" >/dev/null 2>&1 && return 0; done
	return 1
}

pkg_installed() {
	case "$PKG" in
	pacman) pacman -Qi "$1" >/dev/null 2>&1 ;;
	apt) dpkg -s "$1" >/dev/null 2>&1 ;;
	dnf) rpm -q "$1" >/dev/null 2>&1 ;;
	zypper) rpm -q "$1" >/dev/null 2>&1 ;;
	apk) apk info -e "$1" >/dev/null 2>&1 ;;
	*) return 1 ;;
	esac
}

pkg_install_batch() {
	local translated=() n
	for n in "$@"; do translated+=("$(pkg_name "$n")"); done
	case "$PKG" in
	pacman) run $SUDO pacman -S --noconfirm --needed "${translated[@]}" ;;
	apt)
		run env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "${translated[@]}"
		;;
	dnf) run $SUDO dnf install -y "${translated[@]}" ;;
	zypper) run $SUDO zypper --non-interactive install "${translated[@]}" ;;
	apk) run $SUDO apk add --no-cache "${translated[@]}" ;;
	*) return 1 ;;
	esac
}

# ════════════════════════════════════════════════════════════════════════════
# UNINSTALL
# ════════════════════════════════════════════════════════════════════════════
if $UNINSTALL; then
	info "uninstalling tty links for $USER_NAME"
	restored=0
	removed=0
	for f in .zshrc .tmux.conf; do
		dst="$USER_HOME/$f"
		if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == *"/tty/${f#.}" ]]; then
			src="$(readlink "$dst")"
			run rm -f "$dst"
			# Newest backup of the same name wins.
			bak=$(ls -1dt "$BACKUP_ROOT"/*/"$f" 2>/dev/null | head -1 || true)
			if [[ -n "$bak" && -e "$bak" ]]; then
				run cp -a "$bak" "$dst"
				echo "  restored $f from $(basename "$(dirname "$bak")")"
				restored=$((restored + 1))
			else
				warn "no backup to restore for $f (was -> $src)"
			fi
			removed=$((removed + 1))
		else
			skip "$f is not a tty symlink"
		fi
	done
	echo ""
	echo "Removed $removed link(s), restored $restored file(s) from $BACKUP_ROOT."
	echo "Login shell was not changed back: run 'chsh -s /bin/bash' to leave zsh."
	echo "Left in place, delete when you are sure: $DOTDIR, $(command -v zsh >/dev/null && echo '~/.oh-my-zsh')"
	exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# 1. PACKAGES
# ════════════════════════════════════════════════════════════════════════════
if $DO_PACKAGES; then
	detect_pkg
	if [[ -z "$PKG" ]]; then
		warn "no supported package manager (pacman/apt/dnf/zypper/apk) found; continuing with configs only"
	elif [[ $EUID -ne 0 ]] && ! have_cmd sudo; then
		warn "not root and sudo is missing; skipping packages"
	else
		# Refresh the index first on apt/apk: a slim container image has an empty
		# one and every install would fail with "unable to locate package".
		case "$PKG" in
		apt)
			info "apt-get update..."
			run $SUDO apt-get update -qq
			;;
		apk)
			info "apk update..."
			run $SUDO apk update
			;;
		esac

		# canonical name -> commands that prove it is present
		packages=(
			"zsh:zsh"
			"git:git"
			"curl:curl"
			"tmux:tmux"
			"vim:vim vi"
			"less:less"
			"htop:htop"
			"btop:btop"
			"ncdu:ncdu"
			"ripgrep:rg"
			"fd:fd fdfind"
			"wget:wget"
			"man-db:man"
			"man-pages:"
			# HTTPS needs this and slim images forget it; without it the self-update
			# check can never reach the repo and fails in silence once a day.
			"ca-certificates:"
		)

		want=()
		already=()
		for entry in "${packages[@]}"; do
			name=${entry%%:*}
			probes=${entry#*:}
			# Package DB first: it knows about tools that put nothing on PATH
			# (man-pages, ca-certificates). Those two have no probe name on purpose,
			# and must land in 'want' rather than be waved through as present.
			if pkg_installed "$(pkg_name "$name")"; then
				already+=("$name")
			elif [[ -n "$probes" ]] && have_cmd $probes; then
				already+=("$name")
			else
				want+=("$name")
			fi
		done

		[[ ${#already[@]} -gt 0 ]] && skip "present: ${already[*]}"

		if [[ ${#want[@]} -gt 0 ]]; then
			info "installing via $PKG: ${want[*]}"
			if ! pkg_install_batch "${want[@]}"; then
				# One unavailable name (btop on an old LTS, fd on a bare image) must
				# not lose you the rest, so retry the batch one at a time.
				warn "batch install failed; installing one by one"
				failed=()
				for name in "${want[@]}"; do
					pkg_install_batch "$name" || failed+=("$(pkg_name "$name")")
				done
				[[ ${#failed[@]} -gt 0 ]] && warn "not installed: ${failed[*]}"
			fi
		else
			skip "all packages already present"
		fi

		if $WITH_TAILSCALE; then
			if have_cmd tailscale; then
				skip "tailscale already installed"
			else
				info "installing tailscale..."
				pkg_install_batch tailscale || warn "tailscale not available via $PKG"
			fi
			if have_cmd systemctl; then
				run $SUDO systemctl enable --now tailscaled 2>/dev/null ||
					warn "could not enable tailscaled"
			else
				warn "no systemd; start tailscaled however this host runs services"
			fi
			info "then run: sudo tailscale up"
		fi
	fi
fi

# ════════════════════════════════════════════════════════════════════════════
# 2. OH-MY-ZSH
# ════════════════════════════════════════════════════════════════════════════
if $DO_DOTFILES; then
	found_omz=""
	for d in "$USER_HOME/.oh-my-zsh" "$USER_HOME/.config/oh-my-zsh" /usr/share/oh-my-zsh; do
		[[ -f "$d/oh-my-zsh.sh" ]] && {
			found_omz="$d"
			break
		}
	done

	if [[ -n "$found_omz" ]]; then
		skip "oh-my-zsh at $found_omz"
	elif ! have_cmd git; then
		warn "git is missing; cannot install oh-my-zsh (tty/zshrc falls back to a plain prompt)"
	else
		info "cloning oh-my-zsh to ~/.oh-my-zsh..."
		# Cloning, not their install.sh: the installer rewrites ~/.zshrc, which we
		# are about to manage ourselves.
		if run as_user git clone --quiet --depth 1 --branch "$OMZ_BRANCH" "$OMZ_REPO" "$USER_HOME/.oh-my-zsh"; then
			info "oh-my-zsh installed at ~/.oh-my-zsh"
		else
			run rm -rf "$USER_HOME/.oh-my-zsh"
			warn "could not clone oh-my-zsh: no route to github.com, or no CA bundle (install ca-certificates)."
			warn "  tty/zshrc falls back to a plain zsh prompt until it shows up"
		fi
	fi
fi

# ════════════════════════════════════════════════════════════════════════════
# 3. DOTFILES: adopt, clone, or copy from a bundle
# ════════════════════════════════════════════════════════════════════════════
DOTFILES_ROOT=""
MODE=""
if $DO_DOTFILES; then
	if [[ -f "$USER_HOME/tty/zshrc" ]]; then
		# The desktop layout: this repo *is* $HOME. Adopt it; do not clone a second
		# copy and do not disturb the desktop configs that are already tracked here.
		DOTFILES_ROOT="$USER_HOME"
		MODE=adopted
		skip "$USER_HOME is already the dotfiles repo; adopting it"
	elif [[ -n "$SOURCE_DIR" ]]; then
		# Offline / no-route-to-GitHub path: bin/tty-push uses this.
		[[ -f "$SOURCE_DIR/tty/zshrc" ]] || die "--source $SOURCE_DIR has no tty/zshrc"
		info "copying tty bundle from $SOURCE_DIR..."
		run as_user mkdir -p "$DOTDIR"
		run as_user cp -a "$SOURCE_DIR/tty/." "$DOTDIR/tty/"
		DOTFILES_ROOT="$DOTDIR"
		if [[ -d "$SOURCE_DIR/.git" ]]; then
			MODE=bundle-linked
		else
			MODE=bundle
		fi
	elif have_cmd git; then
		if [[ -d "$DOTDIR/.git" ]]; then
			info "updating ~/.dotfiles..."
			run as_user git -C "$DOTDIR" pull --ff-only --quiet ||
				warn "could not fast-forward ~/.dotfiles; leaving the existing copy"
			DOTFILES_ROOT="$DOTDIR"
			MODE=clone
		else
			# Which branch? --branch / DOTFILES_BRANCH, then main, then master, then
			# the remote's default. The default is tried LAST on purpose: on a repo
			# whose HEAD still points at an old branch name it hands back a tree with
			# no tty/ at all, and that failure is invisible until a shell starts up
			# broken. Each candidate is checked for tty/zshrc before it is accepted.
			cands=()
			[[ -n "$BRANCH" ]] && cands+=("$BRANCH")
			cands+=(main master "")
			for try_branch in "${cands[@]}"; do
				label="$try_branch"
				[[ -n "$label" ]] || label="<remote default>"
				info "cloning $label of $REPO_URL (sparse: tty + this script only)..."
				run rm -rf "$DOTDIR"
				# --filter + --sparse keep the desktop's 40 MB of committed binaries out
				# of the checkout. Non-cone patterns, because cone mode can only take a
				# whole directory and bin/ is exactly the part we do not want. Both need
				# a reasonably modern git, so fall back to a plain shallow clone.
				clone_args=(--quiet --depth 1 --filter=blob:none --no-checkout)
				plain_args=(--quiet --depth 1)
				if [[ -n "$try_branch" ]]; then
					clone_args+=(--branch "$try_branch")
					plain_args+=(--branch "$try_branch")
				fi
				if ! run as_user git clone "${clone_args[@]}" "$REPO_URL" "$DOTDIR" ||
					! run as_user git -C "$DOTDIR" sparse-checkout set --no-cone '/tty/' '/bin/setup-tty.sh' ||
					! run as_user git -C "$DOTDIR" checkout --quiet; then
					warn "sparse clone of $label failed (git too old, or $REPO_URL unreachable); retrying plain shallow"
					run rm -rf "$DOTDIR"
					if ! run as_user git clone "${plain_args[@]}" "$REPO_URL" "$DOTDIR"; then
						warn "cannot clone $label"
						continue
					fi
				fi
				if [[ -f "$DOTDIR/tty/zshrc" ]]; then
					BRANCH="$try_branch"
					break
				fi
				warn "$label has no tty/zshrc in it — skipping"
				run rm -rf "$DOTDIR"
			done
			[[ -f "$DOTDIR/tty/zshrc" ]] ||
				die "no branch of $REPO_URL gave me a tty/zshrc — pass --branch NAME, or --source DIR to install from a bundle"
			DOTFILES_ROOT="$DOTDIR"
			MODE=clone
		fi
	else
		warn "no git and no --source DIR: cannot install the configs"
	fi

	[[ -n "$DOTFILES_ROOT" && -f "$DOTFILES_ROOT/tty/zshrc" ]] ||
		die "tty/zshrc not found after setup (DOTFILES_ROOT=$DOTFILES_ROOT)"
	info "config source: $DOTFILES_ROOT/tty (mode: $MODE)"
fi

# ════════════════════════════════════════════════════════════════════════════
# 4. LINK ~/.zshrc and ~/.tmux.conf
# ════════════════════════════════════════════════════════════════════════════
if $DO_DOTFILES; then
	STAMP=$(date +%Y%m-%dT%H%M%S)
	linked=0
	for f in zshrc tmux.conf; do
		src="$DOTFILES_ROOT/tty/$f"
		dst="$USER_HOME/.$f"

		if [[ $MODE != adopted && ! -f "$src" ]]; then
			skip "tty/$f does not exist in $DOTFILES_ROOT"
			continue
		fi

		# On the desktop layout the tracked files stay put: ~/.zshrc there is a shim
		# that sources tty/zshrc, and ~/.tmux.conf is the sway-era config. Replacing
		# either would be a silent rewrite of a tracked file.
		if [[ $MODE == adopted ]]; then
			if [[ $f == zshrc ]]; then
				if grep -q 'tty/zshrc' "$dst" 2>/dev/null; then
					skip "~/.zshrc already loads $DOTFILES_ROOT/tty/zshrc"
				else
					warn "~/.zshrc is the tracked desktop file and does not load tty/zshrc."
					warn "  add this line to it (or run with --source to install a copy):"
					warn "    source \"\$HOME/tty/zshrc\""
				fi
			else
				skip "~/.tmux.conf is the tracked desktop config; leaving it alone"
			fi
			continue
		fi

		if $COPY_FILES; then
			if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
				run as_user mkdir -p "$BACKUP_ROOT/$STAMP"
				run as_user cp -a "$dst" "$BACKUP_ROOT/$STAMP/$f"
				info "backed up old .$f to $BACKUP_ROOT/$STAMP/$f"
			fi
			run as_user cp -a "$src" "$dst"
			linked=$((linked + 1))
			continue
		fi

		if [[ -L "$dst" ]]; then
			if [[ "$(readlink -m "$dst")" == "$(readlink -m "$src")" ]]; then
				skip ".$f already linked"
				continue
			fi
			run as_user mkdir -p "$BACKUP_ROOT/$STAMP"
			run as_user mv "$dst" "$BACKUP_ROOT/$STAMP/$f"
			info "moved the old dangling .$f into $BACKUP_ROOT/$STAMP"
		elif [[ -e "$dst" ]]; then
			run as_user mkdir -p "$BACKUP_ROOT/$STAMP"
			run as_user mv "$dst" "$BACKUP_ROOT/$STAMP/$f"
			info "backed up old .$f to $BACKUP_ROOT/$STAMP/$f"
		fi

		run as_user ln -sfn "$src" "$dst"
		linked=$((linked + 1))
		info "linked .$f -> $src"
	done
fi

# ════════════════════════════════════════════════════════════════════════════
# 5. LOGIN SHELL
# ════════════════════════════════════════════════════════════════════════════
if $DO_DOTFILES && ! $NO_CHSH; then
	zsh_bin=$(command -v zsh || true)
	if [[ -z "$zsh_bin" ]]; then
		warn "zsh not installed; leaving the login shell alone"
	else
		current_shell=$(getent passwd "$USER_NAME" | cut -d: -f7)
		if [[ "$current_shell" == "$zsh_bin" ]]; then
			skip "login shell already $zsh_bin"
		elif [[ $EUID -ne 0 && ! -t 0 ]]; then
			# chsh would ask for a password we cannot type through 'curl | bash'.
			warn "not root and no terminal: run 'chsh -s $zsh_bin' yourself"
		elif ! have_cmd chsh; then
			# BusyBox ships no chsh, so Alpine (and anything else minimal) needs the
			# shadow package for it, or usermod directly.
			warn "no chsh on this distro (BusyBox). Either: $SUDO ${PKG:-pkg} install shadow, or run:"
			warn "    $SUDO usermod -s $zsh_bin $USER_NAME"
		else
			info "setting login shell to $zsh_bin..."
			run $SUDO chsh -s "$zsh_bin" "$USER_NAME" ||
				warn "chsh failed; run 'chsh -s $zsh_bin' yourself"
		fi
	fi
fi

# ════════════════════════════════════════════════════════════════════════════
# 6. VERIFY
# ════════════════════════════════════════════════════════════════════════════
if $DO_DOTFILES && ! $DRY; then
	if [[ -f "$USER_HOME/.zshrc" ]] && have_cmd zsh; then
		if run as_user zsh -n "$USER_HOME/.zshrc"; then
			info "~/.zshrc parses"
		else
			warn "~/.zshrc did not parse; check 'zsh -n ~/.zshrc'"
		fi
		# Prove the whole file loads for real. SSH_TTY is stripped so the tmux
		# autoattach does not hijack the check, and the -c string reports where it
		# ended up.
		out=$(as_user env -u SSH_TTY DOTFILES_TMUX_AUTOATTACH=0 zsh -i -c \
			'printf "%s|%s|%s" "${ZSH:-none}" "${ZSH_THEME:-none}" "$EDITOR"' </dev/null 2>&1 | tail -1) || true
		info "interactive zsh: theme/source = ${out:-no output}"
	fi

	if have_cmd tmux && [[ -f "$USER_HOME/.tmux.conf" ]]; then
		# -L takes a socket *name*, not a path, so it must not contain a slash.
		sock="setup-tty-verify-$$"
		if tmux_err=$(as_user tmux -f "$USER_HOME/.tmux.conf" -L "$sock" start-server 2>&1); then
			if [[ -n "$tmux_err" ]]; then
				warn "~/.tmux.conf loaded with complaints: $tmux_err"
			else
				info "~/.tmux.conf loads"
			fi
			as_user tmux -L "$sock" kill-server 2>/dev/null || true
		else
			warn "~/.tmux.conf did not load: ${tmux_err:-tmux failed to start}"
		fi
	fi

	if $DO_PACKAGES && ! have_cmd sshd && [[ ! -x /usr/sbin/sshd ]] && [[ ! -x /usr/bin/sshd ]]; then
		warn "no sshd found: this host cannot be SSHed into until you install and enable one"
	fi
fi

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════
echo ""
info "done ($MODE)"
if $DRY; then
	echo "Nothing was changed (dry run)."
else
	echo "Next steps:"
	echo "  1. log out and back in (or: exec zsh) to pick up the new shell + config"
	echo "  2. SSH logins now land in tmux session 'ssh' and reattach on reconnect."
	echo "       opt out per host:  echo 'DOTFILES_TMUX_AUTOATTACH=0' >> ~/.zshrc.local"
	echo "  3. machine-specific paths (nvm, deno, SDKs) go in ~/.zshrc.local —"
	echo "       see $DOTFILES_ROOT/tty/zshrc.local.example"
	echo "  4. updates: checked every 13 days in the background, or run:"
	echo "       ${DOTFILES_ROOT:-$HOME/.dotfiles}/tty/update.sh run"
	echo "  5. machine-specific edits: ~/.zshrc.local, never ~/.zshrc"
	echo ""
	echo "Backups of replaced files: $BACKUP_ROOT"
	echo "Undo this install: $(dirname "${BASH_SOURCE[0]:-$0}")/setup-tty.sh --uninstall"
fi

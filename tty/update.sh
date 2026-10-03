#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# dotfiles :: tty — self-update, following oh-my-zsh's approach: a cooldown
# stamp, a lock directory so ten open shells do one check, the network work in
# the background, and at most one line of output, shown once.
#
#   update.sh check    cooldown-gated. This is what tty/zshrc runs at startup.
#   update.sh run      check now, in the foreground, and say what happened.
#   update.sh status   what it knows, without touching the network.
#
# It updates $DOTFILES_ROOT — probed as ~/.dotfiles, then $HOME — which is the
# same repo this file lives in. On the desktop that repo is the entire home
# directory, so it only ever fast-forwards when no tracked file is modified, and
# never merges when you have local commits. Anything it declines to do, it tells
# you instead.
#
# oh-my-zsh itself is updated by its own mechanism (zstyle ':omz:update' in
# tty/zshrc); this script does not touch it.
#
# Knobs, all environment variables:
#   DOTFILES_UPDATE_DISABLE=1    no checks at all (also disables oh-my-zsh's)
#   DOTFILES_UPDATE_DAYS=13      cooldown between checks, in days
#   DOTFILES_UPDATE_MODE=auto    auto    fast-forward, then tell you once
#                                notify  fetch and tell you; you apply it
#                                off     same as DISABLE for check
# ─────────────────────────────────────────────────────────────────────────────
set -eu

CMD="${1:-check}"
case "$CMD" in
check | run | status) ;;
*)
	echo "usage: $(basename "$0") [check|run|status]" >&2
	exit 2
	;;
esac

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-tty"
DAYS="${DOTFILES_UPDATE_DAYS:-13}"
MODE="${DOTFILES_UPDATE_MODE:-auto}"
STAMP="$STATE_DIR/last-check"
LOCK="$STATE_DIR/lock"
LOG="$STATE_DIR/update.log"

say() {
	# Only `run` talks; `check` runs on every shell start and must be silent.
	[ "$CMD" = run ] && printf '%s\n' "$*" || true
}

log() {
	printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true
}

notify() {
	log "$*"
	# Inside tmux the message goes to the status line, which you are looking at.
	# Otherwise leave it for the next shell to print, once.
	if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
		tmux display-message "dotfiles: $*" 2>/dev/null ||
			printf 'dotfiles: %s\n' "$*" >"$STATE_DIR/notice"
	else
		printf 'dotfiles: %s\n' "$*" >"$STATE_DIR/notice"
	fi
}

# Last checked, in days since the epoch (oh-my-zsh uses the same unit). Empty or
# unreadable means "never"; the redirect is guarded so a missing stamp does not
# put a shell error on the user's screen.
last_epoch() {
	if [ -f "$STAMP" ]; then
		tr -dc '0-9' <"$STAMP" 2>/dev/null || true
	fi
}

# ── find the repo ────────────────────────────────────────────────────────────
root="${DOTFILES_ROOT:-}"
if [ -z "$root" ]; then
	for dir in "$HOME/.dotfiles" "$HOME"; do
		[ -f "$dir/tty/update.sh" ] && {
			root="$dir"
			break
		}
	done
fi

if [ -z "$root" ] || ! command -v git >/dev/null 2>&1; then
	say "no git repo with tty/ found (set DOTFILES_ROOT); nothing to update"
	exit 0
fi

if [ ! -d "$root/.git" ]; then
	say "$root is not a git repo (installed from a bundle): auto-update off"
	exit 0
fi

mkdir -p "$STATE_DIR"

# ── status: read-only, no lock, no network ───────────────────────────────────
if [ "$CMD" = status ]; then
	last=$(last_epoch)
	if [ -n "$last" ]; then
		checked="$(date -d "@$((last * 86400))" 2>/dev/null ||
			date -r "$last" 2>/dev/null || echo "epoch day $last")"
	else
		checked="never"
	fi
	printf 'repo     %s\n' "$root"
	printf 'branch   %s\n' "$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
	printf 'head     %s\n' "$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo '?')"
	printf 'tracked  origin/%s (as of the last fetch)\n' "$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
	printf 'behind   %s\n' "$(git -C "$root" rev-list --count "HEAD..origin/$(git -C "$root" rev-parse --abbrev-ref HEAD)" 2>/dev/null || echo 'n/a')"
	printf 'modified %s\n' "$([ -n "$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)" ] && echo 'yes (auto-update will wait)' || echo 'no')"
	printf 'last check  %s  (every %s days, mode %s)\n' "$checked" "$DAYS" "$MODE"
	printf 'state    %s\n' "$STATE_DIR"
	[ -f "$LOG" ] && {
		printf 'recent log:\n'
		tail -n 5 "$LOG" | sed 's/^/  /'
	}
	exit 0
fi

# ── check / run ──────────────────────────────────────────────────────────────
if [ "$CMD" = check ]; then
	if [ "${DOTFILES_UPDATE_DISABLE:-0}" = 1 ] || [ "$MODE" = off ]; then exit 0; fi
fi

today=$(( $(date +%s) / 86400 ))
last=$(last_epoch)
last=${last:-0}
if [ "$CMD" = check ] && [ $((today - last)) -lt "$DAYS" ]; then
	exit 0
fi

# One check at a time. A lock older than an hour came from a fetch that died, or
# from a laptop that slept through one, so it is fair game.
if ! mkdir "$LOCK" 2>/dev/null; then
	if find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null | grep -q .; then
		rm -rf "$LOCK"
		mkdir "$LOCK" 2>/dev/null || exit 0
	else
		say "another update check is already running"
		exit 0
	fi
fi
trap 'rm -rf "$LOCK"' EXIT INT TERM

# Stamp before working, so a host with no route to the repo does not retry the
# network on every single shell.
printf '%s\n' "$today" >"$STAMP"

branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
case "$branch" in
'' | HEAD)
	say "detached HEAD in $root; leaving it alone"
	exit 0
	;;
esac

# Never wait for a password, and never hang a shell over a dead link.
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT
if command -v timeout >/dev/null 2>&1; then
	TMO="timeout 30"
else
	TMO=""
fi

if ! $TMO git -C "$root" fetch --quiet origin >>"$LOG" 2>&1; then
	notify "could not fetch origin (offline? try: git -C $root fetch)"
	exit 0
fi

remote="origin/$branch"
behind=$(git -C "$root" rev-list --count "HEAD..$remote" 2>/dev/null || echo 0)
ahead=$(git -C "$root" rev-list --count "$remote..HEAD" 2>/dev/null || echo 0)
before=$(git -C "$root" rev-parse --short HEAD)

if [ "$behind" -eq 0 ]; then
	say "up to date ($before on $branch)"
	exit 0
fi

if [ "$ahead" -gt 0 ]; then
	notify "$behind commit(s) on origin/$branch, but $ahead local commit(s) — nothing merged (git -C $root status)"
	exit 0
fi

# Tracked modifications only: on the desktop this repo is $HOME, and scanning
# every untracked file in it would cost more than the update itself. git refuses
# to clobber local edits anyway; checking first just keeps the decision obvious.
if [ -n "$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
	notify "$behind commit(s) available, working tree modified — nothing merged (git -C $root pull --ff-only)"
	exit 0
fi

if [ "$MODE" != auto ]; then
	notify "$behind commit(s) available on origin/$branch (run: $0 run)"
	exit 0
fi

if ! $TMO git -C "$root" merge --ff-only --quiet "$remote" >>"$LOG" 2>&1; then
	notify "$behind commit(s) available but would not fast-forward (git -C $root status)"
	exit 0
fi

after=$(git -C "$root" rev-parse --short HEAD)
say "updated $before -> $after on $branch"
notify "updated $before -> $after (new config applies to new shells)"

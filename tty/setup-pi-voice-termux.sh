#!/bin/sh
# Set up pi voice (STT capture + TTS) on a Termux host. Run AFTER ~/.dotfiles/bin/install.
#
#   sh ~/.dotfiles/tty/setup-pi-voice-termux.sh [--force]
#
# Why this exists: install links only tty/zshrc and tty/tmux.conf. It does not touch
# ~/.pi/, ~/.zshrc.local, or ~/bin — those are machine-local by design. And Termux
# cannot use pi-voice-stt's built-in capture at all: its ffmpeg is built
# --disable-indevs --enable-indev=lavfi, so there is no live audio input format, it
# does not link libpulse, and /dev/snd is sandbox-blocked. Hence the shim.
#
# This script does NOT invent config. It fetches the real config from the f creds
# store, so it refuses to run on a box with no store rather than writing a guess that
# silently misconfigures STT. It does not commit to guessing whether stt.json was
# packed from a desktop: it shows you what it pulled and you delete the capture block
# yourself if this is not Termux.
set -u

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Detect Termux. Under `set -u`, dash errors on some unset-var expansions and
# `${VAR:-}` is not dependable there, so match with a case pattern, which is exempt.
# An earlier basename/dirname version made this script print "not Termux" while
# running on Termux, because the guard short-circuited before the comparison.
case "${PREFIX:-}" in
	/data/data/com.termux/files/usr) TERMUX=true ;;
	*)                             TERMUX=false ;;
esac
[ -n "${TERMUX_VERSION:-}" ] && TERMUX=true

if [ "$TERMUX" != true ]; then
	say "not Termux (PREFIX=${PREFIX:-unset}) -- nothing to do; the built-in capture default is correct here"
	exit 0
fi

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

command -v f >/dev/null 2>&1 || die "f not on PATH — run ~/.dotfiles/bin/install first"
command -v termux-microphone-record >/dev/null 2>&1 || die \
	"termux-microphone-record missing: pkg install termux-api, and install the Termux:API app (F-Droid), then grant microphone permission"

# `f creds status` exits 0 whether locked or unlocked -- it only reports. Piping it
# into grep makes `set -u` irrelevant but the real trap is the exit code: a guard on
# `f creds status ||` never fires. Check the text instead.
CREDS_STATE=$(f creds status 2>&1) || die "could not read creds status: $CREDS_STATE"
case "$CREDS_STATE" in
	*locked*) die "creds store is locked -- run: f creds unlock" ;;
esac

# ── configs from the store ───────────────────────────────────────────────────
# unpack refuses to clobber without --force (and writes .bak even with it).
if $FORCE; then UNPACK="f creds files unpack --force"; else UNPACK="f creds files unpack"; fi
# shellcheck disable=SC2086
$UNPACK ~/.pi/agent/stt.json ~/.pi/agent/tts.json ~/.pi/agent/stt.env ~/.pi/agent/README-stt-tts.md ||
	die "could not unpack the pi voice configs — were they ever packed? check: f creds files ls"

grep -q '"capture"' "$HOME/.pi/agent/stt.json" || say \
	"note: packed stt.json has NO capture block. Fine on a desktop (ffmpeg/pulse works);\nwrong here on Termux. If this is Termux, delete the packed copy, fix it on a Termux\nhost, and repack."

# ── the capture shim ─────────────────────────────────────────────────────────
mkdir -p "$HOME/bin"
SRC="$SCRIPT_DIR"
for s in termux-capture pi-stt-where; do
	[ -f "$SRC/$s" ] || { say "skip $s (not in tty/)"; continue; }
	if [ -e "$HOME/bin/$s" ] && ! $FORCE; then
		say "keep  ~/bin/$s (already exists; --force to overwrite)"
		continue
	fi
	cp -p "$SRC/$s" "$HOME/bin/$s" && chmod 700 "$HOME/bin/$s" && say "installed ~/bin/$s"
done

# ── PATH + TMPDIR, the only ~/.zshrc.local bits this needs ───────────────────
LOCAL="$HOME/.zshrc.local"
if [ ! -f "$LOCAL" ]; then
	printf '%s\n' "# machine-specific zsh; see tty/zshrc.local.example" >"$LOCAL" && chmod 600 "$LOCAL"
fi
grep -q 'HOME/bin' "$LOCAL" 2>/dev/null || {
	printf '%s\n' 'export PATH="$HOME/bin:$PATH"' >>"$LOCAL"
	say "added PATH to ~/.zshrc.local"
}
# Deliberately no PI_STT_CONFIG: it is read once at process start AND it replaces the
# config path instead of merging, so a capture-only sidecar loses provider/cleanup.
if grep -q 'PI_STT_CONFIG' "$LOCAL" 2>/dev/null; then
	say "WARNING: PI_STT_CONFIG is exported in ~/.zshrc.local. Remove it: it replaces"
	say "  ~/.pi/agent/stt.json entirely rather than merging, silently losing provider"
	say "  and cleanup. Capture belongs inline in stt.json."
fi

# ── verify, do not assume ────────────────────────────────────────────────────
say ""
say "verify (no restart needed to read the file):"
say "  pi-stt-where        # must show ffmpegPath=.../bin/termux-capture"
say "  /tts test           # in pi"
say ""
say "then: quit pi and relaunch it (a fresh process), keep the Termux window ON SCREEN"
say "while dictating, and press Ctrl+R. Android denies the mic to backgrounded Termux,"
say "including over SSH and tmux, and there is no config for that."

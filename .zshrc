# ─────────────────────────────────────────────────────────────────────────────
# ~/.zshrc — this laptop. Thin on purpose.
#
# All shell behaviour lives in tty/zshrc, which is also what gets installed to
# ~/.zshrc on headless hosts by bin/setup-tty.sh. Editing it here changes the
# desktop and every SSH box at once; machine-specific things (this machine's
# toolchains and paths) go in ~/.zshrc.local, which tty/zshrc sources last.
#
# The pre-2026-10 desktop version is in git: `git show HEAD~1:.zshrc` from the
# first commit after the switch, or `git log -p --follow .zshrc`.
# ─────────────────────────────────────────────────────────────────────────────

source "$HOME/tty/zshrc"

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

# Machine-specific: this laptop only. Others override per host in their own
# ~/.zshrc.local or via the environment; tty/zshrc keeps autoattach on by default.
#
# Must be set BEFORE sourcing tty/zshrc: its tmux autoattach block reads this
# var and execs away, and ~/.zshrc.local is only sourced after that.
# (This host is a local terminal, not an SSH login, so it never fired anyway.)
export DOTFILES_TMUX_AUTOATTACH=0

source "$HOME/tty/zshrc"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

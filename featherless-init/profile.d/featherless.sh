# Sourced by login shells, which sshd starts only for an interactive login.
# Linked as 00-featherless.sh so tmux starts before any other profile script
# prints; their output, the banner among them, lands inside the session.

# /etc/profile resets PATH on most distros; keep the container's.
if [ -n "${FEATHERLESS_CONTAINER_PATH:-}" ]; then
  PATH=$FEATHERLESS_CONTAINER_PATH
  export PATH
fi

if [ -n "${TMUX:-}" ]; then
  # The banner shows once per tmux session, in the window that created it.
  if tmux show-environment FEATHERLESS_BANNER_SHOWN >/dev/null 2>&1; then
    FEATHERLESS_BANNER_SHOWN=1
    export FEATHERLESS_BANNER_SHOWN
  else
    tmux set-environment FEATHERLESS_BANNER_SHOWN 1
  fi
elif [ -n "${SSH_TTY:-}" ] && [ ! -e "$HOME/.no_auto_tmux" ] && command -v tmux >/dev/null 2>&1; then
  # Every SSH login lands in the shared session "default". Opt out with: touch ~/.no_auto_tmux
  # tmux refuses a terminal the image has no terminfo entry for (xterm-ghostty, xterm-kitty).
  featherless_term=xterm-256color
  for featherless_dir in "${TERMINFO:-}" "$HOME/.terminfo" /etc/terminfo /lib/terminfo /usr/share/terminfo /usr/lib/terminfo; do
    if [ -n "$featherless_dir" ] && [ -n "${TERM:-}" ] && [ -e "$featherless_dir/$(printf %.1s "$TERM")/$TERM" ]; then
      featherless_term=$TERM
    fi
  done
  # -u: the distribution's locale script has not run yet in this shell.
  TERM=$featherless_term tmux -u new-session -A -s default && exit
  unset featherless_term featherless_dir
fi

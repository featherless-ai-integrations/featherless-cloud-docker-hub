# Sourced by login shells, which sshd starts only for an interactive login.

# /etc/profile resets PATH on most distros; keep the container's.
if [ -n "${FEATHERLESS_CONTAINER_PATH:-}" ]; then
  PATH=$FEATHERLESS_CONTAINER_PATH
  export PATH
fi

# Every SSH login lands in the shared session "default". Opt out with: touch ~/.no_auto_tmux
if [ -n "${SSH_TTY:-}" ] && [ -z "${TMUX:-}" ] && [ ! -e "$HOME/.no_auto_tmux" ] && command -v tmux >/dev/null 2>&1; then
  tmux new-session -A -s default && exit
fi

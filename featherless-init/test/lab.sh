#!/usr/bin/env bash
# Runs featherless-init from a Docker image mount in each base image, the way an
# instance Pod mounts it, and checks the instance command and the SSH side.
#
#   test/lab.sh [image...]        defaults to a matrix of common base images
#
# Needs Docker 28+ (image mounts) and network access for package installs.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
arch=$(docker info --format '{{.Architecture}}' | sed 's/x86_64/amd64/;s/aarch64/arm64/')
bundle=featherless-init:lab-$arch
images=("$@")
[ ${#images[@]} -gt 0 ] || images=(ubuntu:24.04 debian:trixie-slim rockylinux/rockylinux:9 fedora:42 alpine:3.22 opensuse/leap:15.6 python:3.12-slim)

docker build -q --platform "linux/$arch" -f "$root/docker-image/featherless-init/Dockerfile" -t "$bundle" "$root" >/dev/null || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"; docker rm -f fl-init-client >/dev/null 2>&1' EXIT
ssh-keygen -q -t ed25519 -N '' -C lab -f "$work/id_ed25519"
mkdir "$work/keys" && cp "$work/id_ed25519.pub" "$work/keys/authorized_keys" && chmod 0755 "$work/keys" && chmod 0444 "$work/keys/authorized_keys"
# A stand-in for the template images' login banner, with the same once-only guard.
cat >"$work/banner.sh" <<'BANNER'
[ "${FEATHERLESS_BANNER_SHOWN:-}" = 1 ] && return 0
FEATHERLESS_BANNER_SHOWN=1
export FEATHERLESS_BANNER_SHOWN
echo LAB-BANNER
BANNER

docker network create fl-init-lab >/dev/null 2>&1
docker rm -f fl-init-client >/dev/null 2>&1
docker run -d --name fl-init-client --network fl-init-lab -v "$work:/lab:ro" alpine:3.22 sleep infinity >/dev/null
docker exec fl-init-client sh -c 'apk add -q openssh-client >/dev/null && install -m 0600 /lab/id_ed25519 /root/id && head -c 1048576 /dev/urandom > /tmp/blob'
opts="-i /root/id -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes"
on() { local host=$1; shift; docker exec fl-init-client ssh $opts "root@$host" "$@"; }
tty_session() { docker exec -e TERM="${3:-xterm-256color}" fl-init-client sh -c "{ sleep 4; printf '%s' \"\$0\"; sleep 2; } | timeout 20 ssh -tt $opts root@$1 2>&1 | tr -d '\r'" "$2"; }
failed=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FAIL  %s: %s\n' "$1" "$2"; failed=1; fi; }

for image in "${images[@]}"; do
  host=fl-init-$(echo "$image" | tr -c 'a-z0-9\n' '-' | sed 's/-*$//')
  docker rm -f "$host" >/dev/null 2>&1
  echo "== $image ($arch)"
  docker run -d --name "$host" --network fl-init-lab --platform "linux/$arch" \
    --mount "type=image,source=$bundle,target=/run/featherless/init" \
    -v "$work/keys:/run/featherless/ssh:ro" -v "$work/banner.sh:/etc/profile.d/10-lab-banner.sh:ro" \
    -e FEATHERLESS_AUTHORIZED_KEYS_PATH=/run/featherless/ssh/authorized_keys -e LAB_IMAGE_VAR=from-container \
    --entrypoint /run/featherless/init/featherless-init "$image" \
    -- sh -c 'trap "echo got-term; exit 7" TERM; echo "instance-command pid=$$"; while :; do sleep 1; done' >/dev/null

  started=$(date +%s)
  until on "$host" true >/dev/null 2>&1; do
    [ $(($(date +%s) - started)) -lt 300 ] || break
    sleep 2
  done
  if ! on "$host" true >/dev/null 2>&1; then
    check "SSH ready" "not after 300 s; init.log: $(docker exec "$host" tail -3 /run/featherless/state/init.log | tr '\n' ' ')"
    docker rm -f "$host" >/dev/null
    continue
  fi
  check "SSH ready after $(($(date +%s) - started)) s" ok

  logs=$(docker logs "$host" 2>&1)
  [ "$logs" = "instance-command pid=1" ] && check "instance command is PID 1, container output is only its own" ok \
    || check "container output" "$logs"

  container_path=$(docker exec "$host" sh -c 'echo $PATH')
  got=$(on "$host" 'echo "$(id -un) $LAB_IMAGE_VAR $PATH"')
  case $got in
    "root from-container "*"$container_path") check "login as root with the container environment" ok ;;
    *) check "environment" "$got (container PATH $container_path)" ;;
  esac

  tty_session "$host" $'\002d' >/dev/null
  sessions=$(on "$host" 'tmux ls -F "#{session_name}"' 2>&1)
  [ "$sessions" = default ] && check "interactive login starts tmux session \"default\"" ok || check "auto tmux" "$sessions"

  banner=$(on "$host" 'pane=$(tmux capture-pane -p -t default -S -100); echo "$(echo "$pane" | grep -c "GPU CLOUD") $(echo "$pane" | grep -c LAB-BANNER)"')
  uptime=$(on "$host" 'tmux capture-pane -p -t default -S -100 | grep -m1 "^Uptime"')
  case $uptime in
    "Uptime"*" min"*) check "the banner shows the container's uptime" ok ;;
    *) check "banner uptime" "${uptime:-none}" ;;
  esac
  [ "$banner" = "1 0" ] && check "the Featherless banner shows inside the new session, the image's own banner does not repeat it" ok \
    || check "banner in session" "GPU CLOUD and LAB-BANNER counts: ${banner:-none}"
  second=$(on "$host" 'tmux new-window -t default; sleep 1; pane=$(tmux capture-pane -p -t default -S -100); echo "$(echo "$pane" | grep -c "GPU CLOUD") $(echo "$pane" | grep -c LAB-BANNER)"; tmux kill-window -t default')
  [ "$second" = "1 0" ] && check "a new window shows the banner too" ok || check "banner in new window" "GPU CLOUD and LAB-BANNER counts: ${second:-none}"

  pane_path=$(on "$host" 'tmux send-keys -t default "echo \$PATH > /tmp/pane-path" Enter; sleep 1; cat /tmp/pane-path')
  case $pane_path in
    *"$container_path") check "login shells keep the container PATH" ok ;;
    *) check "pane PATH" "$pane_path (container $container_path)" ;;
  esac

  on "$host" 'touch ~/.no_auto_tmux'
  plain=$(tty_session "$host" $'echo "tmux=[$TMUX]"; exit\n' | grep -o 'tmux=\[[^]]*\]' | tail -1)
  [ "$plain" = "tmux=[]" ] && check "~/.no_auto_tmux opts out" ok || check "opt-out" "${plain:-no shell output}"
  on "$host" 'rm ~/.no_auto_tmux'

  on "$host" 'tmux kill-server'
  tty_session "$host" $'\002d' xterm-ghostty >/dev/null
  sessions=$(on "$host" 'tmux ls -F "#{session_name}"' 2>&1)
  [ "$sessions" = default ] && check "a terminal the image has no terminfo for still starts tmux" ok || check "unknown TERM" "$sessions"

  docker exec fl-init-client sh -c "scp -q -i /root/id -P 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR /tmp/blob root@$host:/tmp/blob && scp -q -i /root/id -P 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@$host:/tmp/blob /tmp/blob.back && cmp -s /tmp/blob /tmp/blob.back" \
    && check "scp round trip" ok || check "scp" "failed"

  docker exec "$host" sh -c 'kill $(cat /run/featherless/state/sshd.pid)'
  sleep 7
  on "$host" true >/dev/null 2>&1 && check "sshd restarts after it is killed" ok || check "sshd restart" "SSH down 7 s after kill"

  on "$host" 'sh -c "sleep 1 &"; nohup sleep 2 >/dev/null 2>&1 &' >/dev/null 2>&1
  sleep 4
  zombies=$(docker exec "$host" sh -c 'for f in /proc/[0-9]*/status; do grep -q "^State:.*Z" "$f" 2>/dev/null && echo "$f"; done' | wc -l | tr -d ' ')
  [ "$zombies" = 0 ] && check "no zombies left by SSH sessions" ok || check "zombies" "$zombies"

  stop_started=$(date +%s)
  docker stop -t 10 "$host" >/dev/null
  code=$(docker inspect -f '{{.State.ExitCode}}' "$host")
  [ "$code" = 7 ] && docker logs "$host" 2>&1 | grep -q got-term \
    && check "SIGTERM reaches the instance command; exit code $code in $(($(date +%s) - stop_started)) s" ok \
    || check "SIGTERM" "exit code $code"

  docker cp "$host:/run/featherless/state/init.log" "$work/init.log" >/dev/null 2>&1 && grep -E 'Installed|Could not|No ' "$work/init.log" | sed 's/^/        /'
  docker rm -f "$host" >/dev/null
done

# An image without a package manager runs its command and gives up on SSH at once.
echo "== busybox:1.37, no package manager"
docker rm -f fl-init-busybox >/dev/null 2>&1
docker run -d --quiet --name fl-init-busybox --platform "linux/$arch" \
  --mount "type=image,source=$bundle,target=/run/featherless/init" \
  --entrypoint /run/featherless/init/featherless-init busybox:1.37 -- sleep infinity >/dev/null
sleep 5
log=$(docker exec fl-init-busybox cat /run/featherless/state/init.log)
case $log in
  *"No sshd; SSH is unavailable"*) check "SSH is reported unavailable without retrying" ok ;;
  *) check "no package manager" "$(echo "$log" | tail -2 | tr '\n' ' ')" ;;
esac
docker rm -f fl-init-busybox >/dev/null

# An image without a shell runs only its command, as it would without featherless-init.
echo "== distroless python3, no shell"
got=$(docker run --rm --quiet --platform "linux/$arch" \
  --mount "type=image,source=$bundle,target=/run/featherless/init" \
  --entrypoint /run/featherless/init/featherless-init gcr.io/distroless/python3-debian12:latest \
  -- python3 -c 'import os; print(os.getpid(), os.path.exists("/run/featherless/state"))' 2>&1)
[ "$got" = "1 False" ] && check "the command runs as PID 1 and nothing else starts" ok || check "no shell" "$got"

# The SSH side needs root; a non-root container's output stays its own.
echo "== debian:trixie-slim as uid 1000"
got=$(docker run --rm --quiet --platform "linux/$arch" --user 1000 \
  --mount "type=image,source=$bundle,target=/run/featherless/init" \
  --entrypoint /run/featherless/init/featherless-init debian:trixie-slim -- sh -c 'echo "$$"' 2>&1)
[ "$got" = 1 ] && check "the command runs as PID 1 and the output is only its own" ok || check "non-root" "$(echo "$got" | tr '\n' ' ')"

exit "$failed"

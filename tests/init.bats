#!/usr/bin/env bats

setup() { SCRIPT="$BATS_TEST_DIRNAME/../scripts/featherless-init"; }

@test "script has valid bash syntax" { bash -n "$SCRIPT"; }

@test "arbitrary commands run alongside platform services" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'trap "exit 0" TERM INT' 'while true; do sleep 1; done' > "$BATS_TEST_TMPDIR/bin/jupyter"
  chmod +x "$BATS_TEST_TMPDIR/bin/jupyter"

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" REQUIRE_MI325X=false ENABLE_SSH=false ENABLE_JUPYTER=true \
    "$SCRIPT" printf 'ok'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting JupyterLab"* ]]
  [[ "$output" == *"Starting custom command"* ]]
  [[ "$output" == *"ok"* ]]
}

@test "serve rejects a configuration with no services" {
  run env REQUIRE_MI325X=false ENABLE_SSH=false ENABLE_JUPYTER=false "$SCRIPT" run
  [ "$status" -ne 0 ]
  [[ "$output" == *"no service or custom command enabled"* ]]
}

@test "service selector rejects unknown services" {
  run env REQUIRE_MI325X=false "$SCRIPT" run invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown service"* ]]
}

@test "service selector and custom command compose" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'trap "exit 0" TERM INT' 'while true; do sleep 1; done' > "$BATS_TEST_TMPDIR/bin/jupyter"
  chmod +x "$BATS_TEST_TMPDIR/bin/jupyter"

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" REQUIRE_MI325X=false ENABLE_SSH=true ENABLE_JUPYTER=false \
    "$SCRIPT" run jupyter -- printf 'ok'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting JupyterLab"* ]]
  [[ "$output" == *"Starting custom command"* ]]
  [[ "$output" == *"ok"* ]]
}

@test "help documents install and run modes" {
  run "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"start [all|ssh|jupyter]"* ]]
}

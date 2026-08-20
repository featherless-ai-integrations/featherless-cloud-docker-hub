#!/usr/bin/env bats

setup() { SCRIPT="$BATS_TEST_DIRNAME/../scripts/featherless-init"; }

@test "script has valid bash syntax" { bash -n "$SCRIPT"; }

@test "arbitrary commands are passed through" {
  run "$SCRIPT" printf 'ok'
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "serve rejects a configuration with no services" {
  run env REQUIRE_MI325X=false ENABLE_SSH=false ENABLE_JUPYTER=false "$SCRIPT" run
  [ "$status" -ne 0 ]
  [[ "$output" == *"no service enabled"* ]]
}

@test "service selector rejects unknown services" {
  run env REQUIRE_MI325X=false "$SCRIPT" run invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown service"* ]]
}

@test "help documents install and run modes" {
  run "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"start [all|ssh|jupyter]"* ]]
}

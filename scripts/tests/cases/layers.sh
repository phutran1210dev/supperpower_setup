# The lib layering: no call goes to a lower layer or round a cycle (tests/layers.pl).

test_lib_layers() {
  local s="$TESTS_DIR/.."
  perl "$TESTS_DIR/layers.pl" "$s/superpowers.sh" "$s"/lib/*.sh "$s"/targets/*.sh > "$WORK/layers.out" 2>&1
  check "no downward calls or cycles: $(tr '\n' ';' < "$WORK/layers.out")" test $? = 0
  # the checker catches both kinds
  mkdir -p "$WORK/layers/lib"
  printf 'log() { :; }\nboth() { lock_get; }\n' > "$WORK/layers/lib/pipeline.sh"
  printf 'lock_get() { log; }\n' > "$WORK/layers/lib/lock.sh"
  printf 'one() { log; cmd_check; }\n' > "$WORK/layers/lib/ui.sh"
  printf 'cmd_check() { :; }\n' > "$WORK/layers/lib/check.sh"
  perl "$TESTS_DIR/layers.pl" "$WORK"/layers/lib/*.sh > "$WORK/layers.out" 2>&1
  check "reports a downward call" contains "$WORK/layers.out" "ui.sh (layer 1) calls cmd_check from check.sh (layer 4, below it)"
  check "reports a cycle" grep -q '^cycle: .*lock.sh.*pipeline.sh\|^cycle: .*pipeline.sh.*lock.sh' "$WORK/layers.out"
}

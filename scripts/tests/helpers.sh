# Test harness: assertions, the bootstrap runner and file/JSON/guard helpers.
# Sourced by run.sh after the environment is set up (WORK, HOME, PATH).

PASS=0 FAIL=0 CURRENT=""
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL [%s] %s\n' "$CURRENT" "$*"; }
check() { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then pass; else fail "$msg"; fi; }
check_not() { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$msg"; else pass; fi; }

# bootstrap PROJECT ARGS... — run with the fixtures
bootstrap() {
  local dir="$1"; shift
  bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" "$@" "$dir" > "$WORK/last.log" 2>&1
}

# manifest DIR — every file and symlink with its content hash / target
manifest() {
  (cd "$1" && find . \( -type f -o -type l \) ! -path './.git/*' | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then echo "$f -> $(readlink "$f")"; else echo "$f $(cksum < "$f" | cut -d' ' -f1)"; fi
  done)
}

json_ok() { perl -MJSON::PP -e 'local $/; JSON::PP->new->decode(<STDIN>)' < "$1"; }
# json_has FILE PERL_EXPR — the expression (over $d) is true
json_has() { SP_EXPR="$2" perl -MJSON::PP -e 'local $/; my $d = JSON::PP->new->decode(<STDIN>); exit(eval($ENV{SP_EXPR}) ? 0 : 1)' < "$1"; }
contains() { grep -qF -- "$2" "$1"; }

# guard FILE FORMAT JSON — run a guard; sets GUARD_RC and GUARD_OUT
guard() {
  GUARD_OUT="$(printf '%s' "$3" | perl "$1" "$2" 2>/dev/null)"
  GUARD_RC=$?
}
blocked() { guard "$@"; [ "$GUARD_RC" -eq 2 ]; }
allowed() { guard "$@"; [ "$GUARD_RC" -eq 0 ] && [ -z "$GUARD_OUT" ]; }

run_test() {
  CURRENT="$1"
  # the shared install always runs: other tests use it
  case "$1" in *"$FILTER"*|test_install_all) ;; *) return 0 ;; esac
  printf '%s\n' "$1"
  "$1"
}

P="$WORK/project"   # a full install shared by the guard tests

# pipe_run CODE — run CODE with the output helpers loaded, plain mode, output in $WORK/pipe.out
pipe_run() {
  ( . "$TESTS_DIR/../lib/ui.sh"; . "$TESTS_DIR/../lib/pipeline.sh"; eval "$1" ) > "$WORK/pipe.out" 2>&1
}

# json_get FILE PERL_PATH — the value at PATH in a JSON file (e.g. '{mcpServers}{"codebase-memory"}{command}')
json_get() { perl -MJSON::PP -0777 -ne "my \$d = decode_json(\$_); my \$v = \$d->$2; print ref \$v ? JSON::PP->new->canonical->encode(\$v) : \$v // ''" "$1"; }

# The lock, .agents/superpowers.lock: what the last run set up, as "KEY: value"
# lines. A header (version, ref, targets, and the options --check re-runs
# with), then one skill: / agent: line per thing of ours, so re-runs and
# uninstall touch only those.

LOCK_REL=".agents/superpowers.lock"
# the lock as it was before this run (install_skills rewrites it)
PREV_LOCK=""

# lock_get KEY [FILE] — KEY's values, one per line, in the lock (or FILE)
lock_get() { local f="${2:-$LOCK_FILE}"; [ -f "$f" ] && sed -n "s/^$1: //p" "$f"; return 0; }
# lock_count KEY — how many KEY: lines the lock has
lock_count() { lock_get "$1" | grep -c . || true; }
locked_skills() { lock_get skill; }
is_locked() { locked_skills | grep -qx "$1"; }

# lock_snapshot — keep the lock as it is now in PREV_LOCK
lock_snapshot() { [ -f "$LOCK_FILE" ] && PREV_LOCK="$(cat "$LOCK_FILE")"; return 0; }
# prev_locked KEY — KEY's values in PREV_LOCK
prev_locked() { printf '%s\n' "$PREV_LOCK" | sed -n "s/^$1: //p"; }

# lock_start — a new lock with this run's header
lock_start() {
  {
    echo "# Managed by the Superpowers bootstrap — https://github.com/obra/superpowers (MIT)"
    echo "version: $SP_VERSION"
    echo "ref: $REF"
    echo "targets: $TARGETS"
    # the non-default options, so --check can reproduce this run
    echo "options: $(run_options)"
  } > "$LOCK_FILE"
}

# lock_add KEY VALUES — append a KEY: line per (non-empty) line of VALUES
lock_add() { printf '%s\n' "$2" | sed -n "/./s/^/$1: /p" >> "$LOCK_FILE"; }

# run_options — this run's non-default options
run_options() {
  local opts=""
  [ "$LINK_MODE" = "copy" ] && opts="$opts --copy"
  [ "$AGENTS" -eq 0 ] && opts="$opts --no-agents"
  [ "$ECC_SKILLS" -eq 0 ] && opts="$opts --no-ecc-skills"
  [ "$SECRET_GUARD" -eq 0 ] && opts="$opts --no-secret-guard"
  [ "$RIPGREP" -eq 0 ] && opts="$opts --no-ripgrep"
  [ "$CODE_MAP" -eq 0 ] && opts="$opts --no-code-map"
  [ "$SECURITY_AUDIT" -eq 0 ] && opts="$opts --no-security-audit"
  { [ "$AGENTS" -eq 1 ] || [ "$ECC_SKILLS" -eq 1 ]; } && opts="$opts --ecc-ref $ECC_REF"
  [ "$SECURITY_AUDIT" -eq 1 ] && opts="$opts --security-audit-ref $SECURITY_AUDIT_REF"
  # the stacks used, detected or not: the --check copy has no manifests
  opts="$opts --stacks ${STACKS:-none}"
  echo "${opts# }"
}

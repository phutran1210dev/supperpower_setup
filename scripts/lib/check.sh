# --check: CI drift detection. Re-runs the bootstrap on a copy of the paths it
# manages, with the targets and options recorded in the lock, and compares the
# copy with the project. Catches hand edits to generated files, files deleted
# by mistake, and output from an older version of this script. The lock records
# the refs used, so a version bump is a re-run with --ref, not drift.

CHECK_PATHS=".agents .claude .github .cursor .codex .devin .windsurf .gemini .vscode .mcp.json AGENTS.md CLAUDE.md GEMINI.md .security-audit/.gitignore"

# manifest DIR — one line per managed file: path, symlink target or content
# hash, and the executable bit
manifest() {
  local p f
  (
    cd "$1" || exit 1
    for p in $CHECK_PATHS; do
      [ -e "$p" ] || [ -L "$p" ] || continue
      find "$p" \( -type f -o -type l \) ! -name '*.bak' ! -path ".agents/bin/*"
    done | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then echo "$f -> $(readlink "$f")"
      else echo "$f $(cksum < "$f" | cut -d' ' -f1)$([ -x "$f" ] && echo ' +x')"
      fi
    done
  )
}

# cmd_check — the --check mode (options recorded by run_options, lib/lock.sh)
cmd_check() {
  [ -f "$LOCK_FILE" ] || die "no $LOCK_REL in $PROJECT_DIR — run the bootstrap first"
  local copy="$TMP_DIR/check" p args drift n f run
  run="$(lock_get targets) $(lock_get options)"
  pipeline_start 3

  stage_begin copy
  mkdir -p "$copy"
  for p in $CHECK_PATHS; do
    if [ -e "$PROJECT_DIR/$p" ] || [ -L "$PROJECT_DIR/$p" ]; then
      mkdir -p "$copy/$(dirname "$p")"
      cp -RP "$PROJECT_DIR/$p" "$copy/$(dirname "$p")/"
    fi
  done
  # reports keep .security-audit/.gitignore after --no-security-audit; a
  # placeholder (outside the manifest) makes the re-run keep it on the copy too
  if [ -n "$(ls -A "$PROJECT_DIR/.security-audit" 2>/dev/null | grep -vx '.gitignore')" ]; then
    mkdir -p "$copy/.security-audit/reports"
  fi
  stage_end "generated paths $(arrow) scratch copy"

  stage_begin rerun
  # shellcheck disable=SC2207 # options are single words
  args=(-y -t "$(normalize_targets "$(lock_get targets)")" --ref "$(lock_get ref)" $(lock_get options))
  [ -n "$SOURCE" ] && args+=(--source "$SOURCE")
  [ -n "$ECC_SOURCE" ] && args+=(--ecc-source "$ECC_SOURCE")
  [ -n "$SECURITY_AUDIT_SOURCE" ] && args+=(--security-audit-source "$SECURITY_AUDIT_SOURCE")
  # rg and codebase-memory binaries and the index are per machine: not part
  # of the comparison
  if ! NO_COLOR=1 SP_RG_NO_DOWNLOAD=1 SP_CM_NO_INSTALL=1 bash "$SCRIPT_DIR/superpowers.sh" "${args[@]}" "$copy" > "$TMP_DIR/check.log" 2>&1; then
    stage_fail
    cat "$TMP_DIR/check.log" >&2
    die "the bootstrap failed on the check copy"
  fi
  stage_end "$run"

  stage_begin compare
  manifest "$PROJECT_DIR" > "$TMP_DIR/have"
  manifest "$copy" > "$TMP_DIR/want"
  drift="$({ diff "$TMP_DIR/have" "$TMP_DIR/want" || true; } | sed -n 's/^[<>] \([^ ]*\).*/\1/p' | sort -u)"
  if [ -z "$drift" ]; then
    stage_end "up to date"
    pipeline_end
    return 0
  fi
  n=0
  for f in $drift; do warn "$f"; n=$((n + 1)); done
  if [ "$n" -eq 1 ]; then stage_end "1 file differs"; else stage_end "$n files differ"; fi
  pipeline_end
  printf '%s\n' "out of date — re-run: $0 -t $run ." >&2
  exit 1
}

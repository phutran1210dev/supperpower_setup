# --check: drift detection against a re-run on a scratch copy.

test_check_drift_on_stderr() {
  local d="$WORK/drifterr"; rm -rf "$d" && bootstrap "$d" -t claude
  perl -pi -e 's/^## Superpowers$/## Superpowers (edited)/' "$d/CLAUDE.md"
  bash "$BOOTSTRAP" -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" --check "$d" > /dev/null 2> "$WORK/drift.err"
  check "drifted files on stderr" contains "$WORK/drift.err" "CLAUDE.md"
}

test_check() {
  local d="$WORK/checked"
  rm -rf "$d" && bootstrap "$d" -t claude,codex
  check "--check passes after install" bootstrap "$d" --check
  perl -pi -e 's/^## Superpowers$/## Superpowers (edited)/' "$d/CLAUDE.md"
  check_not "--check fails on an edited block" bootstrap "$d" --check
  check "--check names the file" contains "$WORK/last.log" "CLAUDE.md"
  bootstrap "$d" -t claude,codex
  rm "$d/.codex/hooks/secret-guard.pl"
  check_not "--check fails on a deleted file" bootstrap "$d" --check
  check "--check names the deleted file" contains "$WORK/last.log" ".codex/hooks/secret-guard.pl"
  bootstrap "$d" -t claude,codex
  check "--check passes after a re-run" bootstrap "$d" --check
  rm -rf "$d" && bootstrap "$d" -t claude,copilot --copy --no-agents
  check "--check reproduces --copy --no-agents" bootstrap "$d" --check
  check_not "--check fails without a lock" bootstrap "$WORK/empty" --check
}

test_check_with_reports_after_opt_out() {
  local d="$WORK/optout"
  rm -rf "$d" && bootstrap "$d" -t claude
  mkdir -p "$d/.security-audit/prod-1" && echo report > "$d/.security-audit/prod-1/REPORT.md"
  bootstrap "$d" -t claude --no-security-audit
  check "reports stay ignored" test -f "$d/.security-audit/.gitignore"
  check "--check passes with reports kept" bootstrap "$d" --check
}

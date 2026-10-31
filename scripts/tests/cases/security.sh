# The security-audit and /release-audit skills and the security-auditor agent.

test_security_audit() {
  local d="$WORK/secaudit" f
  rm -rf "$d" && mkdir -p "$d" && git -C "$d" init -q
  check "bootstrap succeeds" bootstrap "$d"
  for f in .agents/skills/security-audit/SKILL.md .agents/skills/security-audit/validate-findings.cjs \
           .agents/skills/release-audit/SKILL.md .claude/skills/security-audit/SKILL.md \
           .github/skills/release-audit/SKILL.md .agents/licenses/security-audit-skill.LICENSE \
           .claude/agents/security-auditor.md .github/agents/security-auditor.md \
           .codex/agents/security-auditor.toml .agents/agents/security-auditor.md \
           .gemini/agents/security-auditor.md \
           .gemini/commands/release-audit.toml .security-audit/.gitignore; do
    check "creates $f" test -f "$d/$f"
  done
  check "lock records the security-audit-skill commit" grep -q '^security-audit: ' "$d/.agents/superpowers.lock"
  check "lock lists both skills" sh -c "grep -qx 'skill: security-audit' '$d/.agents/superpowers.lock' && grep -qx 'skill: release-audit' '$d/.agents/superpowers.lock'"
  check "CLAUDE.md lists /release-audit" contains "$d/CLAUDE.md" '| `release-audit` |'
  check "release-audit takes the environment" contains "$d/.agents/skills/release-audit/SKILL.md" '$ARGUMENTS'
  check "Gemini command passes {{args}}" contains "$d/.gemini/commands/release-audit.toml" '{{args}}'
  check "Claude auditor preloads the skill" contains "$d/.claude/agents/security-auditor.md" "  - security-audit"
  check "Copilot auditor: no skills key" test "$(grep -c '^skills:' "$d/.github/agents/security-auditor.md")" = 0
  check "Antigravity auditor preloads the skill" contains "$d/.agents/agents/security-auditor.md" "  - security-audit"
  check "Gemini auditor: no skills key (strict schema)" test "$(grep -c '^skills:' "$d/.gemini/agents/security-auditor.md")" = 0
  check "reports are git-ignored" git -C "$d" check-ignore -q .security-audit/staging-20261031-abc1234/REPORT.md
  check_not "the ignore file itself is committed" git -C "$d" check-ignore -q .security-audit/.gitignore
  check "--check passes" bootstrap "$d" --check
  rm "$d/.security-audit/.gitignore"
  check_not "--check fails on a deleted .security-audit/.gitignore" bootstrap "$d" --check
  check "--check names it" contains "$WORK/last.log" ".security-audit/.gitignore"
  bootstrap "$d"

  # --no-security-audit: everything above goes, Superpowers stays
  check "re-run with --no-security-audit" bootstrap "$d" --no-security-audit
  for f in .agents/skills/security-audit .agents/skills/release-audit .claude/skills/security-audit \
           .github/skills/release-audit .agents/licenses/security-audit-skill.LICENSE \
           .claude/agents/security-auditor.md .codex/agents/security-auditor.toml .agents/agents/security-auditor.md .gemini/agents/security-auditor.md \
           .gemini/commands .security-audit; do
    check_not "removes $f" test -e "$d/$f"
  done
  check_not "no dangling .claude/skills link" test -L "$d/.claude/skills/security-audit"
  check_not "no dangling .github/skills link" test -L "$d/.github/skills/release-audit"
  check "keeps Superpowers" test -f "$d/.agents/skills/brainstorming/SKILL.md"
  check "keeps ECC agents" test -f "$d/.claude/agents/planner.md"
  check_not "CLAUDE.md drops release-audit" contains "$d/CLAUDE.md" 'release-audit'
  check "lock records the option" grep -q '^options: .*--no-security-audit' "$d/.agents/superpowers.lock"
  check "--check reproduces --no-security-audit" bootstrap "$d" --check

  # --no-agents keeps the auditor: it belongs to the security audit, not ECC
  check "re-run with --no-agents" bootstrap "$d" --no-agents
  check "auditor kept" test -f "$d/.claude/agents/security-auditor.md"
  check_not "ECC agents gone" test -e "$d/.claude/agents/planner.md"
  check_not "ECC license gone" test -e "$d/.agents/licenses/everything-claude-code.LICENSE"

  # uninstall keeps audit reports (and their ignore file); removes the rest
  mkdir -p "$d/.security-audit/uat-1" && echo report > "$d/.security-audit/uat-1/REPORT.md"
  check "uninstall succeeds" bootstrap "$d" --uninstall
  check "uninstall keeps reports" test -f "$d/.security-audit/uat-1/REPORT.md"
  check "uninstall keeps reports ignored" test -f "$d/.security-audit/.gitignore"
  check_not "uninstall removes the auditor" test -e "$d/.claude/agents/security-auditor.md"
  check_not "uninstall removes the skill" test -e "$d/.agents/skills/security-audit"
}

test_security_audit_own_skill_kept() {
  # a security-audit skill installed some other way (npx skills add) is not overwritten
  local d="$WORK/ownaudit"
  rm -rf "$d" && mkdir -p "$d/.agents/skills/security-audit" && echo mine > "$d/.agents/skills/security-audit/SKILL.md"
  bootstrap "$d" -t claude
  check "warns" contains "$WORK/last.log" ".agents/skills/security-audit already exists"
  check "own skill kept" test "$(cat "$d/.agents/skills/security-audit/SKILL.md")" = mine
  check_not "not in the lock" grep -qx 'skill: security-audit' "$d/.agents/superpowers.lock"
  check "release-audit still installed" test -f "$d/.agents/skills/release-audit/SKILL.md"
  bootstrap "$d" --uninstall
  check "uninstall leaves it" test "$(cat "$d/.agents/skills/security-audit/SKILL.md")" = mine
}

test_both_audit_skills_taken() {
  local d="$WORK/taken" n
  rm -rf "$d" && mkdir -p "$d/.agents/skills/security-audit" "$d/.agents/skills/release-audit"
  for n in security-audit release-audit; do echo mine > "$d/.agents/skills/$n/SKILL.md"; done
  check "bootstrap succeeds" bootstrap "$d" -t claude
  check "summary printed" grep -q "^ready in " "$WORK/last.log"
}

test_own_gemini_command_kept() {
  local d="$WORK/gemcmd"
  rm -rf "$d" && mkdir -p "$d/.gemini/commands" && echo 'prompt = "mine"' > "$d/.gemini/commands/release-audit.toml"
  bootstrap "$d" -t gemini
  check "warns" contains "$WORK/last.log" ".gemini/commands/release-audit.toml already exists"
  check "not overwritten" test "$(cat "$d/.gemini/commands/release-audit.toml")" = 'prompt = "mine"'
  bootstrap "$d" -t gemini --no-security-audit
  check "not deleted by --no-security-audit" test -f "$d/.gemini/commands/release-audit.toml"
  bootstrap "$d" --uninstall
  check "not deleted by uninstall" test -f "$d/.gemini/commands/release-audit.toml"
}

# GitHub Copilot: .github/skills (→ .agents/skills), copilot-instructions.md
# block, secret-file and search guards (.github/hooks). Agents: lib/agents.sh.

COPILOT_GUARD=".github/hooks/secret-guard.pl"
COPILOT_GUARD_CONFIG=".github/hooks/superpowers-secret-guard.json"
COPILOT_SEARCH=".github/hooks/search-guard.pl"
COPILOT_SEARCH_CONFIG=".github/hooks/superpowers-search-guard.json"

setup_copilot() {
  expose_skills ".github/skills"
  # copilot-instructions.md is applied to every chat request; an
  # .instructions.md file is only attached when its applyTo matches a file in
  # play, so the bootstrap goes in a managed block here.
  upsert_block "$PROJECT_DIR/.github/copilot-instructions.md" "$TMP_DIR/block-full.md"
  remove_legacy_copilot_files
  # .github/hooks/*.json: Copilot CLI, the cloud agent and VS Code
  if [ "$SECRET_GUARD" -eq 1 ]; then
    write_secret_guard "$COPILOT_GUARD"
    install_template copilot-guard.json "$COPILOT_GUARD_CONFIG" GUARD "$COPILOT_GUARD"
  else
    rm -f "$PROJECT_DIR/$COPILOT_GUARD" "$PROJECT_DIR/$COPILOT_GUARD_CONFIG"
  fi
  if [ "$RIPGREP" -eq 1 ]; then
    write_search_guard "$COPILOT_SEARCH"
    install_template copilot-guard.json "$COPILOT_SEARCH_CONFIG" GUARD "$COPILOT_SEARCH"
  else
    rm -f "$PROJECT_DIR/$COPILOT_SEARCH" "$PROJECT_DIR/$COPILOT_SEARCH_CONFIG"
  fi
  rmdir "$PROJECT_DIR/.github/hooks" 2>/dev/null || true
}

# Files earlier versions of the bootstrap wrote: .github/instructions/ and the
# sp-* prompt files (skills are slash commands in VS Code, as everywhere else).
remove_legacy_copilot_files() {
  local rel
  rm -f "$PROJECT_DIR/.github/instructions/superpowers.instructions.md"
  for rel in $(prev_locked prompt); do rm -f "${PROJECT_DIR:?}/$rel"; done
  rmdir "$PROJECT_DIR/.github/instructions" "$PROJECT_DIR/.github/prompts" 2>/dev/null || true
}

teardown_copilot() {
  unrecommend GitHub.copilot-chat
  unexpose_skills ".github/skills"
  remove_block "$PROJECT_DIR/.github/copilot-instructions.md"
  remove_legacy_copilot_files
  rm -f "$PROJECT_DIR/$COPILOT_GUARD" "$PROJECT_DIR/$COPILOT_GUARD_CONFIG" \
    "$PROJECT_DIR/$COPILOT_SEARCH" "$PROJECT_DIR/$COPILOT_SEARCH_CONFIG"
  rmdir "$PROJECT_DIR/.github/hooks" "$PROJECT_DIR/.github" 2>/dev/null || true
}

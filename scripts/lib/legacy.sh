# Migration from the first layout of the bootstrap (.superpowers/, loose Claude
# skills + hook, .cursor/skills, unused VS Code keys). Newer leftovers are
# cleaned by each target's setup (see remove_legacy_* helpers).

cleanup_legacy() {
  [ -d "$PROJECT_DIR/.superpowers" ] || return 0
  ok "migrating from the old .superpowers/ layout"
  unexpose_skills ".claude/skills"
  unexpose_skills ".cursor/skills"
  unexpose_skills ".github/skills"
  unexpose_skills ".agents/skills"
  remove_block "$PROJECT_DIR/CLAUDE.md"
  if [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    json_edit "$PROJECT_DIR/.claude/settings.json" "$(claude_settings_clean)"
  fi
  if [ -f "$PROJECT_DIR/.vscode/settings.json" ]; then
    json_edit "$PROJECT_DIR/.vscode/settings.json" '
      delete_key($d, "chat.useAgentSkills");
      delete_key($d, "chat.useAgentsMdFile");
      delete_key($d, "files.associations", "*.mdc");'
  fi
  if [ -f "$PROJECT_DIR/.vscode/extensions.json" ]; then
    json_edit "$PROJECT_DIR/.vscode/extensions.json" '
      drop_values($d, "recommendations", ["GitHub.copilot"]);'
  fi
  rm -rf "$PROJECT_DIR/.superpowers"
  ok "removed .superpowers/"
}

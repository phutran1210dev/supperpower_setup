# Claude Code: .claude/skills (→ .agents/skills), SessionStart hook,
# secret-file guard (PreToolUse + permissions.deny), search guard (PreToolUse on
# Bash), CLAUDE.md block. Agents: lib/agents.sh.

CLAUDE_HOOK=".claude/hooks/superpowers-session-start.sh"
CLAUDE_GUARD=".claude/hooks/secret-guard.pl"
CLAUDE_SEARCH=".claude/hooks/search-guard.pl"
# plugin an earlier version of the bootstrap enabled; removed from settings
LEGACY_CLAUDE_PLUGIN="superpowers@claude-plugins-official"

# json_edit code for .claude/settings.json: drop our hooks, deny rules and the
# plugin entries an earlier version added.
claude_settings_clean() {
  cat <<EOF
drop_entries(\$d, 'hooks', 'SessionStart', qr{superpowers-session-start|\\.superpowers/hooks/});
drop_entries(\$d, 'hooks', 'PreToolUse', qr{secret-guard|search-guard});
drop_values(\$d, 'permissions', 'deny', [$(secret_read_rules)]);
delete_key(\$d, 'enabledPlugins', '$LEGACY_CLAUDE_PLUGIN');
delete_key(\$d, 'extraKnownMarketplaces', 'claude-plugins-official');
EOF
}

setup_claude() {
  expose_skills ".claude/skills"
  # Runs at startup, /clear and after compaction.
  write_session_hook "$CLAUDE_HOOK" claude
  # CLAUDE.md is Claude Code's project instructions file. The hook already
  # injects the full using-superpowers body, so the short block is enough here;
  # it also covers sessions where the hook doesn't run (untrusted folder).
  upsert_block "$PROJECT_DIR/CLAUDE.md" "$TMP_DIR/block-claude.md"
  local edit
  edit="$(claude_settings_clean)
    add_entry(\$d, 'hooks', 'SessionStart', { matcher => 'startup|clear|compact', hooks => [{ type => 'command',
      command => 'bash \"\$CLAUDE_PROJECT_DIR/$CLAUDE_HOOK\"' }] });"
  if [ "$SECRET_GUARD" -eq 1 ]; then
    write_secret_guard "$CLAUDE_GUARD"
    # no matcher: every tool, so MCP and future file tools are covered too
    edit="$edit
      add_entry(\$d, 'hooks', 'PreToolUse', { hooks => [{ type => 'command',
        command => 'perl \"\$CLAUDE_PROJECT_DIR/$CLAUDE_GUARD\" claude' }] });
      add_values(\$d, 'permissions', 'deny', [$(secret_read_rules)]);"
  else
    rm -f "$PROJECT_DIR/$CLAUDE_GUARD"
  fi
  if [ "$RIPGREP" -eq 1 ]; then
    write_search_guard "$CLAUDE_SEARCH"
    edit="$edit
      add_entry(\$d, 'hooks', 'PreToolUse', { matcher => 'Bash', hooks => [{ type => 'command',
        command => 'perl \"\$CLAUDE_PROJECT_DIR/$CLAUDE_SEARCH\" claude' }] });"
  else
    rm -f "$PROJECT_DIR/$CLAUDE_SEARCH"
  fi
  json_edit "$PROJECT_DIR/.claude/settings.json" "$edit"
}

teardown_claude() {
  unrecommend anthropic.claude-code
  unexpose_skills ".claude/skills"
  rm -f "$PROJECT_DIR/$CLAUDE_HOOK" "$PROJECT_DIR/$CLAUDE_GUARD" "$PROJECT_DIR/$CLAUDE_SEARCH"
  rmdir "$(dirname "$PROJECT_DIR/$CLAUDE_HOOK")" 2>/dev/null || true
  remove_block "$PROJECT_DIR/CLAUDE.md"
  if [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    json_edit "$PROJECT_DIR/.claude/settings.json" "$(claude_settings_clean)"
  fi
  rmdir "$PROJECT_DIR/.claude" 2>/dev/null || true
}

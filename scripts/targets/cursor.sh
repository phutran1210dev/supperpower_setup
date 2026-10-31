# Cursor: reads .agents/skills natively (and .claude/agents); sessionStart hook,
# secret-file and search guards (.cursor/hooks.json), an always-apply rule, and
# deny rules for the Cursor CLI (.cursor/cli.json).

CURSOR_HOOK=".cursor/hooks/superpowers-session-start.sh"
CURSOR_GUARD=".cursor/hooks/secret-guard.pl"
CURSOR_SEARCH=".cursor/hooks/search-guard.pl"
CURSOR_GUARD_EVENTS="beforeReadFile beforeShellExecution"

# json_edit code for .cursor/hooks.json: drop our entries
cursor_hooks_clean() {
  local event
  echo "drop_entries(\$d, 'hooks', 'sessionStart', qr{superpowers-session-start});"
  for event in $CURSOR_GUARD_EVENTS; do
    echo "drop_entries(\$d, 'hooks', '$event', qr{secret-guard|search-guard});"
  done
  # a version key alone is not worth keeping
  echo "delete \$d->{version} unless \$d->{hooks};"
}

setup_cursor() {
  # Same bootstrap as the Superpowers Cursor plugin (hooks-cursor.json), as a
  # project hook. The rule keeps the short block for sessions without hooks.
  write_session_hook "$CURSOR_HOOK" cursor
  local edit event
  edit="$(cursor_hooks_clean)
    \$d->{version} //= 1;
    add_entry(\$d, 'hooks', 'sessionStart', { command => 'bash $CURSOR_HOOK' });"
  if [ "$SECRET_GUARD" -eq 1 ]; then
    # .cursorignore is not enough: Cursor's docs say terminal and MCP tools
    # ignore it, so the guard hooks reads and shell commands
    write_secret_guard "$CURSOR_GUARD"
    for event in $CURSOR_GUARD_EVENTS; do
      edit="$edit add_entry(\$d, 'hooks', '$event', { command => 'perl $CURSOR_GUARD cursor' });"
    done
    json_edit "$PROJECT_DIR/.cursor/cli.json" "add_values(\$d, 'permissions', 'deny', [$(secret_read_rules)]);"
  else
    remove_cursor_guard
  fi
  if [ "$RIPGREP" -eq 1 ]; then
    write_search_guard "$CURSOR_SEARCH"
    edit="$edit add_entry(\$d, 'hooks', 'beforeShellExecution', { command => 'perl $CURSOR_SEARCH cursor' });"
  else
    rm -f "$PROJECT_DIR/$CURSOR_SEARCH"
  fi
  json_edit "$PROJECT_DIR/.cursor/hooks.json" "$edit"
  write_rule .cursor/rules/superpowers.mdc \
    $'description: Superpowers skills bootstrap (managed by the Superpowers bootstrap)\nalwaysApply: true' \
    block-claude.md
}

remove_cursor_guard() {
  rm -f "$PROJECT_DIR/$CURSOR_GUARD"
  if [ -f "$PROJECT_DIR/.cursor/cli.json" ]; then
    json_edit "$PROJECT_DIR/.cursor/cli.json" "drop_values(\$d, 'permissions', 'deny', [$(secret_read_rules)]);"
  fi
}

teardown_cursor() {
  rm -f "$PROJECT_DIR/$CURSOR_HOOK" "$PROJECT_DIR/$CURSOR_SEARCH" "$PROJECT_DIR/.cursor/rules/superpowers.mdc"
  remove_cursor_guard
  if [ -f "$PROJECT_DIR/.cursor/hooks.json" ]; then
    json_edit "$PROJECT_DIR/.cursor/hooks.json" "$(cursor_hooks_clean)"
  fi
  rmdir "$PROJECT_DIR/.cursor/hooks" "$PROJECT_DIR/.cursor/rules" "$PROJECT_DIR/.cursor" 2>/dev/null || true
}
